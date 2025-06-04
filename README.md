This is repository is a collection of libraries and tools to collect and analyze the compilation
profiles of OCaml programs.

The main objective is to harvest data and knowledge about the performance of the OCaml compiler
in the opam ecosystem and track the effect of various PRs on the OCaml compiler performance.

**WARNING**: You must disable opam's build sandboxing (remove the
`wrap-build-commands` entry in `.opam/config`) in order for the compiler to be
able to store the timings file in a temporary directory.

# How to create an flambda2 switch

## Automated approach (recommended)

Use the provided Python script to automate the entire process:

```console
# Create a package variant for a specific commit (checksum will be calculated automatically)
$ python3 create_flambda2_switch.py --name my-variant --commit 82e4553f8d75eb4e6f8e94cd9bf90369968f64d5

# Create both the package variant and the opam switch
$ python3 create_flambda2_switch.py --name my-variant --commit 82e4553f8d75eb4e6f8e94cd9bf90369968f64d5 --create-switch

# Provide a custom checksum if you already know it
$ python3 create_flambda2_switch.py --name my-variant --commit abc123def --checksum sha256=your-checksum-here
```

The script will:
1. Clone or update the `opam-repository-flambda` repository
2. Create a new package variant from the template
3. Update the opam file with your specified commit and calculated checksum
4. Optionally create the opam switch (if `--create-switch` is provided)

Run `python3 create_flambda2_switch.py --help` for all available options.

Note: in certain situations, actually creating the switch might fail because new
patches are needed or old patches no longer apply. In this case, you must fall
back to the manual approach and figure it out. Good luck!

## Manual approach

If you prefer to do it manually:

1. Clone https://github.com/bclement-ocp/opam-repository-flambda somewhere and
   go to branch `with-extensions`.

2. Create a switch configuration with the branch that you're interested in by
   copying the template (replace "NAME" with the name you want for your
   variant):

   ```console
   $ cd packages/ocaml-variants/
   $ cp -r ocaml-variants.5.2.0+{flambda2-82e4553f,NAME}
   ```

3. Edit the opam file in `ocaml-variants.5.2.0+NAME/opam`. You need to change
   the following lines to match the commit you want to use and its sha256sum.

   ```opam
   url {
     src: "https://github.com/ocaml-flambda/flambda-backend/archive/82e4553f8d75eb4e6f8e94cd9bf90369968f64d5.tar.gz"
     checksum: ["sha256=c390e80899a92df4b39685987247b202bb0ce992084bd5c6139f1a029f39d43d"]
   }
   ```

4. Create an opam switch with this configuration

   ```console
   $ opam update with-extensions # Will fail the first time
   $ opam switch create 5.2.0+NAME --repos with-extensions=/path/to/opam-repository-flambda,default
   ```

# Running Benchmarks

## JSON Configuration Runner (recommended)

Use the `json_runner` executable to run benchmarks with JSON configuration files instead of hardcoded OCaml scripts:

```console
# Build the runner
$ dune build runner/json_runner.exe

# Run with a configuration file
$ ./_build/default/runner/json_runner.exe examples/simple_config.json

# See example configuration format
$ ./_build/default/runner/json_runner.exe --example
```

### Configuration Format

The JSON configuration file supports the following fields:

- `log`: Path where benchmark logs will be written
- `n`: Number of samples to collect per package (default: 1)
- `slices`: List of compilation phases to profile (e.g., `["typing", "occur_rec"]`)
- `retry`: Number of retry attempts for failed operations (default: 3)
- `with_filesize`: Whether to collect file size information (default: false)
- `with_test`: Whether to install packages with tests using `-t` flag (default: false)
- `switches`: List of OCaml switch names to benchmark
- `context`: List of packages to install as context (dependencies, default: empty list)
- `pkgs`: List of packages to benchmark
- `status_file`: Path to store benchmark progress/status

### Package Format

Packages can be specified as objects with `name` and `version` fields:

```json
{
  "pkgs": [
    {"name": "ocamlfind", "version": "1.9.1"},
    {"name": "zarith", "version": "1.12"}
  ]
}
```

### Example Configurations

See the `examples/` directory for sample configurations:
- `examples/simple_config.json` - Basic benchmark setup
