#!/usr/bin/env python3
"""
Script to automate the creation of flambda2 switches for OCaml performance monitoring.

This script automates the process described in the README for creating flambda2 switches:
1. Clones the opam-repository-flambda repository
2. Creates a new switch configuration from template
3. Updates the opam file with specified commit and checksum
4. Creates the opam switch

Usage:
    python create_flambda2_switch.py --name my-variant --commit 82e4553f8d75eb4e6f8e94cd9bf90369968f64d5 --checksum sha256=c390e80899a92df4b39685987247b202bb0ce992084bd5c6139f1a029f39d43d
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
import hashlib
import urllib.request


def run_command(cmd, cwd=None, check=True, capture_output=False):
    """Run a shell command with error handling."""
    print(f"Running: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            check=check,
            shell=isinstance(cmd, str),
            capture_output=capture_output,
            text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        print(f"Command failed with exit code {e.returncode}")
        if capture_output and e.stdout:
            print(f"stdout: {e.stdout}")
        if capture_output and e.stderr:
            print(f"stderr: {e.stderr}")
        raise


def calculate_sha256(url):
    """Download and calculate SHA256 checksum of a file."""
    print(f"Downloading {url} to calculate checksum...")
    with urllib.request.urlopen(url) as response:
        sha256_hash = hashlib.sha256()
        for chunk in iter(lambda: response.read(4096), b""):
            sha256_hash.update(chunk)
        return sha256_hash.hexdigest()


def clone_opam_repository(repo_dir):
    """Clone the opam-repository-flambda repository."""
    repo_url = "https://github.com/bclement-ocp/opam-repository-flambda"

    if repo_dir.exists():
        print(f"Repository already exists at {repo_dir}")
        # Update existing repository
        run_command(["git", "fetch"], cwd=repo_dir)
        run_command(["git", "checkout", "with-extensions"], cwd=repo_dir)
        run_command(["git", "pull"], cwd=repo_dir)
    else:
        print(f"Cloning repository to {repo_dir}")
        run_command(["git", "clone", "--branch", "with-extensions", repo_url, str(repo_dir)])


def create_variant_package(
    repo_dir, variant_name, commit_hash,
    user="ocaml-flambda", repo="flambda-backend", checksum=None
):
    """Create a new variant package from the template."""
    packages_dir = repo_dir / "packages" / "ocaml-variants"
    template_dir = packages_dir / "ocaml-variants.5.2.0+flambda2-82e4553f"
    variant_dir = packages_dir / f"ocaml-variants.5.2.0+{variant_name}"

    if not template_dir.exists():
        raise FileNotFoundError(f"Template directory not found: {template_dir}")

    if variant_dir.exists():
        print(f"Variant directory already exists: {variant_dir}")
        response = input("Do you want to overwrite it? (y/N): ")
        if response.lower() != 'y':
            print("Aborted.")
            return False
        shutil.rmtree(variant_dir)

    print(f"Creating variant package: {variant_dir}")
    shutil.copytree(template_dir, variant_dir)

    # Update the opam file
    opam_file = variant_dir / "opam"

    # Generate URL and calculate checksum if not provided
    url = f"https://github.com/{user}/{repo}/archive/{commit_hash}.tar.gz"

    if checksum is None:
        print("No checksum provided, calculating...")
        checksum_value = calculate_sha256(url)
        checksum = f"sha256={checksum_value}"
    else:
        # Extract just the hash value if full checksum format is provided
        if checksum.startswith("sha256="):
            checksum_value = checksum[7:]
        else:
            checksum_value = checksum
            checksum = f"sha256={checksum}"

    # Read and update opam file
    with open(opam_file, 'r') as f:
        content = f.read()

    # Replace the specific URL and checksum strings from the template
    template_url = "https://github.com/ocaml-flambda/flambda-backend/archive/82e4553f8d75eb4e6f8e94cd9bf90369968f64d5.tar.gz"
    template_checksum = "sha256=c390e80899a92df4b39685987247b202bb0ce992084bd5c6139f1a029f39d43d"

    # Replace URL
    content = content.replace(template_url, url)

    # Replace checksum
    content = content.replace(template_checksum, checksum)

    with open(opam_file, 'w') as f:
        f.write(content)

    print(f"Updated opam file with commit {commit_hash}")
    return True


def create_opam_switch(repo_dir, variant_name):
    """Create the opam switch."""
    switch_name = f"5.2.0+{variant_name}"

    print("Updating opam repositories...")
    run_command(["opam", "update", "with-extensions"], check=False)  # This might fail first time

    print(f"Creating opam switch: {switch_name}")
    repos_arg = f"with-extensions={repo_dir},default"

    # Check if switch already exists
    result = run_command(["opam", "switch", "list", "--short"], capture_output=True)
    existing_switches = result.stdout.strip().split('\n') if result.stdout.strip() else []

    if switch_name in existing_switches:
        print(f"Switch {switch_name} already exists.")
        response = input("Do you want to remove and recreate it? (y/N): ")
        if response.lower() == 'y':
            run_command(["opam", "switch", "remove", switch_name])
        else:
            print("Using existing switch.")
            return switch_name

    run_command([
        "opam", "switch", "create", switch_name,
        "--repos", repos_arg
    ])

    return switch_name


def main():
    parser = argparse.ArgumentParser(
        description="Automate flambda2 switch creation for OCaml performance monitoring",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create switch package with auto-calculated checksum
  %(prog)s --name my-test --commit 82e4553f8d75eb4e6f8e94cd9bf90369968f64d5

  # Create switch package with provided checksum
  %(prog)s --name my-test --commit abc123def --checksum c390e80899a92df4b39685987247b202bb0ce992084bd5c6139f1a029f39d43d

  # Use custom repository directory
  %(prog)s --name my-test --commit abc123def --repo-dir /path/to/opam-repo

  # Create both package and switch
  %(prog)s --name my-test --commit abc123def --create-switch
        """
    )

    parser.add_argument(
        "--name",
        required=True,
        help="Name for the flambda2 variant (will be used as 5.2.0+NAME)"
    )

    parser.add_argument(
        "--commit",
        required=True,
        help="Git commit hash from flambda-backend repository"
    )

    parser.add_argument(
        "--checksum",
        help="SHA256 checksum of the source archive (will be calculated if not provided)"
    )

    parser.add_argument(
        "--repo-dir",
        type=Path,
        default=Path.home() / "opam-repository-flambda",
        help="Directory to clone/use opam-repository-flambda (default: ~/opam-repository-flambda)"
    )

    parser.add_argument(
        "--user",
        default="ocaml-flambda",
        help="Name of the GitHub user to take the commit from"
    )

    parser.add_argument(
        "--repo",
        default="flambda-backend",
        help="Name of the GitHub repository to take the commit from"
    )

    parser.add_argument(
        "--skip-clone",
        action="store_true",
        help="Skip cloning/updating the repository (assume it already exists)"
    )

    parser.add_argument(
        "--create-switch",
        action="store_true",
        help="Also create the opam switch after creating the package"
    )

    args = parser.parse_args()

    try:
        # Step 1: Clone repository
        if not args.skip_clone:
            clone_opam_repository(args.repo_dir)
        else:
            if not args.repo_dir.exists():
                print(f"Error: Repository directory {args.repo_dir} does not exist")
                sys.exit(1)

        # Step 2: Create variant package
        success = create_variant_package(
            args.repo_dir, args.name, args.commit,
            user=args.user, repo=args.repo, checksum=args.checksum
        )
        if not success:
            sys.exit(1)

        # Step 3: Create opam switch (only if --create-switch is specified)
        if args.create_switch:
            switch_name = create_opam_switch(args.repo_dir, args.name)
            print(f"\nSuccess! Created package variant and switch: {switch_name}")
            print(f"To use this switch, run: opam switch {switch_name}")
        else:
            print(f"\nSuccess! Created package variant: 5.2.0+{args.name}")
            print("Use --create-switch to also create the opam switch")

    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
