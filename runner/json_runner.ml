open Printf

type package_spec = {
  name : string;
  version : string;
}

type config = {
  log : string;
  n : int;
  slices : string list;
  retry : int;
  with_filesize : bool;
  with_test : bool;
  switches : string list;
  context : package_spec list;
  pkgs : package_spec list;
  status_file : string;
}

let package_spec_of_yojson = function
  | `Assoc [("name", `String name); ("version", `String version)]
  | `Assoc [("version", `String version); ("name", `String name)] ->
    Ok {name; version}
  | `List [`String name; `String version] ->
    Ok {name; version}
  | _ -> Error "Expected package spec as {\"name\": \"...\", \"version\": \"...\"} or [\"name\", \"version\"]"

let package_spec_list_of_yojson json =
  let rec aux acc = function
    | [] -> Ok (List.rev acc)
    | x :: xs ->
      match package_spec_of_yojson x with
      | Ok pkg -> aux (pkg :: acc) xs
      | Error e -> Error e
  in
  match json with
  | `List pkgs -> aux [] pkgs
  | _ -> Error "Expected list of packages"

let string_list_of_yojson = function
  | `List items ->
    let rec aux acc = function
      | [] -> Ok (List.rev acc)
      | `String s :: rest -> aux (s :: acc) rest
      | _ -> Error "Expected list of strings"
    in
    aux [] items
  | _ -> Error "Expected list"

let config_of_yojson json =
  let open Yojson.Safe.Util in
  try
    let log = json |> member "log" |> to_string in
    let n = json |> member "n" |> to_int_option |> Option.value ~default:1 in
    let slices_json = json |> member "slices" in
    let slices = match string_list_of_yojson slices_json with
      | Ok s -> s
      | Error e -> failwith e
    in
    let retry = json |> member "retry" |> to_int_option |> Option.value ~default:3 in
    let with_filesize = json |> member "with_filesize" |> to_bool_option |> Option.value ~default:false in
    let with_test = json |> member "with_test" |> to_bool_option |> Option.value ~default:false in
    let switches_json = json |> member "switches" in
    let switches = match string_list_of_yojson switches_json with
      | Ok s -> s
      | Error e -> failwith e
    in
    let context_json = json |> member "context" in
    let context = match context_json with
      | `Null -> []
      | _ -> match package_spec_list_of_yojson context_json with
        | Ok c -> c
        | Error e -> failwith e
    in
    let pkgs_json = json |> member "pkgs" in
    let pkgs = match package_spec_list_of_yojson pkgs_json with
      | Ok p -> p
      | Error e -> failwith e
    in
    let status_file = json |> member "status_file" |> to_string in
    Ok {log; n; slices; retry; with_filesize; with_test; switches; context; pkgs; status_file}
  with
  | exn -> Error (Printexc.to_string exn)

let load_config filename =
  try
    let json = Yojson.Safe.from_file filename in
    config_of_yojson json
  with
  | Sys_error e -> Error ("File error: " ^ e)
  | Yojson.Json_error e -> Error ("JSON parse error: " ^ e)

let package_spec_to_pkg spec = Pkg.make spec.name spec.version

let run_from_config config =
  let context_pkgs = List.map package_spec_to_pkg config.context in
  let pkgs_tuples = List.map (fun spec -> (spec.name, spec.version)) config.pkgs in
  Runner.run
    ~log:config.log
    ~n:config.n
    ~slices:config.slices
    ~retry:config.retry
    ~with_filesize:config.with_filesize
    ~with_test:config.with_test
    ~switches:config.switches
    ~context:context_pkgs
    ~pkgs:pkgs_tuples
    ~status_file:config.status_file

let print_example_config () =
  let example = {|{
  "log": "logs/benchmark.log",
  "slices": ["typing", "occur_rec"],
  "switches": ["5.3.0+occur_rec_profiling", "5.3.0+occur_rec_marking"],
  "pkgs": [
    {"name": "ocamlfind", "version": "1.9.1"},
    {"name": "num", "version": "1.4"},
    {"name": "zarith", "version": "1.12"}
  ],
  "status_file": "status/run.json"
}

Optional fields with defaults:
  "n": 1,           // Number of samples (default: 1)
  "retry": 3,       // Retry attempts (default: 3)
  "with_filesize": false,  // Collect file sizes (default: false)
  "with_test": false,      // Install with tests using -t flag (default: false)
  "context": []     // Context packages (default: empty list)
|} in
  print_endline "Example configuration:";
  print_endline example

let () =
  if Array.length Sys.argv < 2 then begin
    eprintf "Usage: %s <config.json> [--example]\n" Sys.argv.(0);
    eprintf "       %s --example  # Show example configuration\n" Sys.argv.(0);
    exit 1
  end;
  
  if Sys.argv.(1) = "--example" then begin
    print_example_config ();
    exit 0
  end;
  
  let config_file = Sys.argv.(1) in
  match load_config config_file with
  | Error e ->
    eprintf "Error loading config: %s\n" e;
    exit 1
  | Ok config ->
    printf "Running benchmark with config from %s\n" config_file;
    printf "Log: %s\n" config.log;
    printf "Samples: %d\n" config.n;
    printf "Switches: %s\n" (String.concat ", " config.switches);
    printf "Packages: %d\n" (List.length config.pkgs);
    run_from_config config