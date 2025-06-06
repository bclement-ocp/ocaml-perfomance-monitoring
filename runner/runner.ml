let output_dir name =
  Filename.concat (Filename.get_temp_dir_name ()) name

let uuid name =
  let rec loop n =
    let guess = output_dir (name ^ string_of_int n) in
    if not (Sys.file_exists guess) then guess
    else loop (n+1)
   in
  let guess = output_dir name in
  if not (Sys.file_exists guess) then guess else
  loop 2

let pkg_dir ~switch ~pkg =
   uuid @@ (switch ^ "-" ^ Pkg.full pkg)


let rec is_prefix_until prefix s len pos =
  pos >= len ||
  (
    prefix.[pos] = s.[pos]
    && is_prefix_until prefix s len (pos + 1)
  )

let is_prefix ~prefix s = is_prefix_until prefix s (String.length prefix) 0


let file_size ~pkg ~switch ~filename kind s =
  Data.File_size {
    origin={pkg;switch};
    key=filename;
    value = { Data.kind; size= (Unix.stat s).st_size}
  }

let rec crawl_dir ~switch ~pkg dir =
  Seq.concat @@ Seq.map (crawl_file ~switch ~pkg)
  @@ Seq.filter (fun (_, path) -> Sys.file_exists path)
  @@ Seq.map (fun f -> f, Filename.concat dir f)
  @@ Array.to_seq (Sys.readdir dir)
and crawl_file ~switch ~pkg (filename,path) =
  if Sys.is_directory path then
    crawl_dir ~switch ~pkg path
  else
    match Filename.extension filename with
    | ".cmt" -> Seq.return (file_size ~filename ~pkg ~switch Cmt path)
    | ".cmo" -> Seq.return (file_size ~filename ~pkg ~switch Cmo path)
    | ".cmx" -> Seq.return (file_size ~filename  ~pkg ~switch  Cmx path)
    | ".cmi" -> Seq.return (file_size ~filename  ~pkg ~switch Cmi path)
    | ".cmti" -> Seq.return (file_size ~filename  ~pkg ~switch Cmti path)
    | _ -> Seq.empty



let read_result ~with_filesize ~build_dir ~slices ~switch ~pkg ~dir =
  let files = Array.to_list @@ Sys.readdir dir in
  let read_file filename =
    if is_prefix ~prefix:"profile" (Filename.basename filename) then
      Some (Parse.profile (Filename.concat dir filename))
    else
      None
  in
  let split_timings l = Seq.map (fun x -> Data.Compilation_profile x) (List.to_seq l) in
  let timings =
    files
    |> List.to_seq
    |> Seq.filter_map read_file
    |> Seq.map (Data.times ~switch ~pkg ~slices)
    |> Seq.concat_map split_timings
  in
  if not with_filesize then timings else
    let sizes =
      crawl_dir ~switch ~pkg build_dir
    in
    Seq.append timings sizes

let (<!>) = Cmds.(<!>)

let rec rmr f =
  if Sys.is_directory f then begin
    Array.iter (fun x -> rmr (Filename.concat f x)) (Sys.readdir f);
    Sys.rmdir f
  end
  else Sys.remove f


let sample ~retry ~log ~slices ~with_filesize ~with_test ~switch ~pkg ~ocamlparam ~opamjobs =
  let dir = pkg_dir ~switch ~pkg in
  let () =  Sys.mkdir dir 0o777 in
  Cmds.execute ~with_test ~retry ~switch ~pkg ~dir ~ocamlparam ~opamjobs <!> Format.dprintf "Failed to install %s" (Pkg.full pkg);
  let build_dir = Cmds.opam_var ~switch ~pkg "build" in
  Seq.iter
    (Log.write_entry log)
    (read_result ~with_filesize ~slices ~switch ~build_dir ~dir ~pkg:(Pkg.full pkg));
  rmr dir


let rec multisample n ~with_filesize ~with_test ~retry ~log ~slices ~switch ~pkg ~ocamlparam ~opamjobs =
  if n = 0 then () else
    begin
      sample ~with_filesize ~with_test ~retry ~log ~switch ~pkg ~slices ~ocamlparam ~opamjobs;
      multisample ~with_filesize ~with_test ~retry (n-1) ~slices ~log  ~pkg ~switch ~ocamlparam ~opamjobs
    end

let pkg_line n ~with_filesize ~with_test ~retry ~log ~slices ~switch pkgs ~ocamlparam ~opamjobs =
  Cmds.remove_pkg ~switch (List.rev pkgs);
  List.iter  (fun pkg ->
      multisample ~with_filesize ~with_test n ~retry ~slices ~log ~switch ~pkg ~ocamlparam ~opamjobs
    ) pkgs


let clean ~switches ~pkgs () = List.iter (fun switch ->
     Cmds.remove_pkg ~switch (List.rev pkgs)
  ) switches

let install_context ~retry ~with_test ~switches ~pkgs =
  match pkgs with
  | [] -> ()
  | _ ->
    List.iter (fun switch ->
        Cmds.install ~retry ~with_test ~switch ~pkgs
        <!> Format.dprintf "Installation failure: %s/%a" switch Fmt.(list string) (List.map Pkg.full pkgs)
      ) switches

let experiment ~retry ~log ~slices ~ocamlparam ~opamjobs {Zipper.switch;pkg;_} =
  sample ~retry ~log ~switch ~slices ~pkg ~ocamlparam ~opamjobs

let start ~n ~retry ~slices ~with_filesize ~with_test ~switches ~status_file ~log_name ~log ~context ~pkgs ~ocamlparam ~opamjobs =
  let () = clean ~switches ~pkgs () in
  let () = install_context ~retry:3 ~with_test:false ~switches ~pkgs:context in
  let z = Zipper.start ~with_filesize ~slices ~retry ~log:log_name ~switches ~pkgs ~sample_size:n in
  Zipper.tracked_iter ~status_file (experiment ~with_filesize ~with_test ~slices ~retry ~log ~ocamlparam ~opamjobs) z



let with_file ?(mode=[Open_wronly; Open_creat; Open_append; Open_binary]) filename f =
  let x = open_out_gen mode 0o777 filename in
  let ppf = Format.formatter_of_out_channel x in
  Fun.protect (fun () -> f ppf)
    ~finally:(fun () -> close_out x)

let with_file_append filename f =
  with_file
    ~mode:[Open_wronly; Open_creat; Open_append; Open_binary] filename f

let restart ~status_file  =
  let z = Zipper.t_of_yojson (Yojson.Safe.from_file status_file) in
  let switches = Zipper.switches z in
  let slices = Zipper.slices z in
  let with_filesize = Zipper.with_filesize z in
  let sampled = z.pkgs.sampled in
  let todo = z.pkgs.todo in
  let () = clean ~switches ~pkgs:todo () in
  let () = install_context ~retry:3 ~with_test:false ~switches ~pkgs:sampled in
  with_file_append z.log (fun log ->
      Zipper.tracked_iter ~status_file
        (experiment ~with_filesize ~with_test:false ~slices ~retry:z.retry ~log ~ocamlparam:[] ~opamjobs:"1") z
    )



let run ~n ~with_filesize ~slices ~retry ~with_test ~status_file ~log:log_name ~switches ~context ~pkgs ~ocamlparam ~opamjobs =
  with_file log_name (fun log ->
      start ~slices ~log ~log_name ~status_file
        ~n
        ~with_filesize
        ~with_test
        ~retry
        ~switches
        ~context
        ~pkgs:(List.map (fun (name,version) -> Pkg.make name version) pkgs)
        ~ocamlparam
        ~opamjobs
    )
