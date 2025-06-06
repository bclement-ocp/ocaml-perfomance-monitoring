let cmd fmt = Format.kasprintf Sys.command fmt

let putenv_fmt key fmt =
  Format.kasprintf (Unix.putenv key) fmt

let set_switch switch ppf = Fmt.pf ppf "eval $(opam env --set-switch --switch=%S)" switch
let with_switch ~switch fmt =
  cmd ("(%t &&" ^^ fmt ^^ ")") (set_switch switch)

let rec with_retry ~msg ~retry f =
  match f (), retry with
  | 0, _ | _, 0 -> 0
  | _, retry ->
    Fmt.(pf stderr) "Error during %t. Retrying %d times.@." msg retry;
    with_retry ~msg ~retry:(retry - 1) f

let reinstall ~retry ~switch ~pkg ~with_test =
  let test_flag = if with_test then "-t" else "" in
  with_retry
    ~msg:(Format.dprintf "reinstallation of %s"  (Pkg.full pkg))
    ~retry
    (fun () -> with_switch ~switch "opam reinstall --no-depexts -b --yes %s %s" test_flag (Pkg.name pkg))

let install ~retry ~with_test ~switch ~pkgs =
  let test_flag = if with_test then "-t" else "" in
  with_retry ~retry
    ~msg:(Format.dprintf "reinstallation of %a"  (Fmt.(list string))  (List.map Pkg.full pkgs))
    (fun () -> with_switch ~switch "opam install --no-depexts -b --yes %s %s" test_flag (String.concat " " @@ List.map Pkg.name pkgs))

let opam_var ~switch ~pkg var =
  let inp, out = Unix.open_process (Format.asprintf "(%t && opam var %s:%s)" (set_switch switch) (Pkg.name pkg) var) in
  let r= input_line inp in
  In_channel.close inp; Out_channel.close out;
  r


let execute ~retry ~dir ~switch ~pkg ~ocamlparam ~opamjobs ~with_test =
  let ocamlparam_str = String.concat "," (List.map (fun (k, v) -> k ^ "=" ^ v) ocamlparam) in
  let full_ocamlparam = ",_,timings=1,dump-into-file=1,dump-dir=" ^ dir ^ (if ocamlparam_str = "" then "" else "," ^ ocamlparam_str) in
  putenv_fmt "OCAMLPARAM" "%s" full_ocamlparam;
  putenv_fmt "OPAMJOBS" "%s" opamjobs;
  reinstall ~retry ~switch ~pkg ~with_test



let (<!>) n err =
  if n = 0 then () else (err Fmt.stderr ; exit n)


let remove_pkg ~switch pkgs =
  cmd "(%t && opam remove --no-depexts --yes %s)" (set_switch switch) (String.concat " " @@ List.map Pkg.name pkgs)
  <!> Format.dprintf "Failed to remove %a" (Fmt.list Fmt.Dump.string) (List.map Pkg.full pkgs)
