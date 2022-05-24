open Common.Id

(* Using a mutable map for now, as the simplest solution. 
We are processing commands sequentially, so the telescope is built naturally, and 
there should be no issue with dependencies between new definitions and previous ones.  *)
let global_decls : (Ast.term * Ast.term) Name.Map.t ref = ref Name.Map.empty
let find x = Name.Map.find x !global_decls
let add x terms = global_decls := Name.Map.add x terms !global_decls
