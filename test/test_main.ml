exception Parse_error of string

module CastCIC = Gcic.Main.Make (Gcic.CastCIC.Executor)

(* let cmd_result =
  let open Vernac.Exec in
  let pprint_cmd_result ppf res = Format.pp_print_string ppf (string_of_cmd_result res) in
  let term_eq = alpha_equal in
  let cmd_eq c1 c2 =
    match c1, c2 with
    | Reduction t1, Reduction t2
    | Elaboration t1, Elaboration t2
    | Inference t1, Inference t2 -> term_eq t1 t2
    | Unit, Unit -> true
    | Definition (n1, t1), Definition (n2, t2) -> n1 = n2 && Kernel.Ast.eq t1 t2
    | _, _ -> false
  in
  Alcotest.testable pprint_cmd_result cmd_eq *)

let run = CastCIC.run
let false_ind = "Inductive false : Type@0 :=."
let bool_ind = "Inductive bool : Type := | false : bool | true : bool."

let list_ind =
  "Inductive list (a : Type) : Type :=\n\
  \  | nil : list a\n\
  \  | cons (hd : a) (tl : list a) : list a\n\
  \  ."

let w_ind =
  "Inductive W (a : Type) (b : a -> Type) : Type :=\n\
  \  | sup (x : a) (f : b x -> W a b) : W a b\n\
  \  .\n\
  \  "

let test_inductive_defs () =
  Alcotest.(check string) "false ind" "OK" (run false_ind);
  Alcotest.(check string) "bool ind" "OK" (run bool_ind);
  Alcotest.(check string) "list ind" "OK" (run list_ind);
  Alcotest.(check string) "W ind" "OK" (run w_ind)

let tests = [ "inductive defs", `Quick, test_inductive_defs ]
