type t = {
  work_dir : string;
  compile_script : string;
  test_script : string;
  coverage_data : string;
}

let file_instrument filename src_dir preamble =
  let read_whole_file filename =
    let ch = open_in filename in
    let s = really_input_string ch (in_channel_length ch) in
    close_in ch;
    s
  in
  let c_code = read_whole_file filename in
  let instr_c_code = preamble ^ c_code in
  let oc = open_out filename in
  Printf.fprintf oc "%s" instr_c_code;
  close_out oc

let file_instrument_all work_dir preamble =
  let rec traverse_file f root_dir =
    let files = Sys.readdir root_dir in
    Array.iter
      (fun file ->
        let file_path = Filename.concat root_dir file in
        if (Unix.lstat file_path).st_kind = Unix.S_LNK then ()
        else if List.mem file !Cmdline.blacklist then ()
        else if Sys.is_directory file_path then traverse_file f file_path
        else if Filename.extension file = ".c" then
          f file_path (Filename.concat work_dir "src") preamble
        else ())
      files
  in
  traverse_file file_instrument work_dir

let init ?(stdio_only = false) work_dir =
  let work_dir =
    if Filename.is_relative work_dir then
      Filename.concat (Unix.getcwd ()) work_dir
    else work_dir
  in
  {
    work_dir;
    compile_script = Filename.concat work_dir "compile.sh";
    test_script = Filename.concat work_dir "test.sh";
    coverage_data = Filename.concat work_dir "coverage.xml";
  }

let simple_compiler compile_script =
  Unix.create_process compile_script [| compile_script |] Unix.stdin Unix.stdout
    Unix.stderr
  |> ignore;
  match Unix.wait () |> snd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n ->
      failwith ("Error " ^ string_of_int n ^ ": " ^ compile_script ^ " failed")
  | _ -> failwith (compile_script ^ " failed")

let make () =
  let jobs =
    if !Cmdline.jobs = 0 then "-j" else "-j" ^ string_of_int !Cmdline.jobs
  in
  Unix.create_process "make" [| "make"; jobs |] Unix.stdin Unix.stdout
    Unix.stderr
  |> ignore;
  match Unix.wait () |> snd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n -> failwith ("Error " ^ string_of_int n ^ ": make failed")
  | _ -> failwith "make failed"

let configure () =
  Unix.create_process "./configure"
    [|
      "./configure";
      "CFLAGS=--coverage -save-temps=obj -Wno-error";
      "CXXFLAGS=--coverage -save-temps=obj";
      "LDFLAGS=-lgcov --coverage";
    |]
    Unix.stdin Unix.stdout Unix.stderr
  |> ignore;
  match Unix.wait () |> snd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n ->
      failwith ("Error " ^ string_of_int n ^ ": configure failed")
  | _ -> failwith "configure failed"

let make_clean () =
  Unix.create_process "make" [| "make"; "clean" |] Unix.stdin Unix.stdout
    Unix.stderr
  |> ignore;
  match Unix.wait () |> snd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n ->
      failwith ("Error " ^ string_of_int n ^ ": make clean failed")
  | _ -> failwith "make clean failed"

let make_distclean () =
  Unix.create_process "make" [| "make"; "distclean" |] Unix.stdin Unix.stdout
    Unix.stderr
  |> ignore;
  match Unix.wait () |> snd with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED n ->
      failwith ("Error " ^ string_of_int n ^ ": make distclean failed")
  | _ -> failwith "make distclean failed"

let configure_and_make () =
  Unix.chdir "src";
  make_clean ();
  make_distclean ();
  configure ();
  make ()

let compile scenario compiler_type =
  match compiler_type with
  | "compile" -> simple_compiler scenario.compile_script
  | "configure-and-make" -> configure_and_make ()
  | _ -> failwith "Unknown compiler"

let run_test test_script name =
  Unix.create_process test_script [| test_script; name |] Unix.stdin Unix.stdout
    Unix.stderr
  |> ignore;
  Unix.wait () |> ignore
