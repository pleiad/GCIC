(** This module specifies the structure of the parsed AST *)
open Common.Id

(** Terms in GCIC *)
type term =
| Var of Name.t
| Universe of int 
| App of term * term 
| Lambda of (Name.t option * term) list * term 
| Prod of (Name.t option * term) list * term 
| Unknown of int
| LetIn of (Name.t * term * term * term)

(** Returns the stringified version of a term *)
val to_string : term -> string 

val eq_term : term -> term -> bool

type command =
| Eval of term
| Check of term * term
| Elaborate of term

val string_of_command : command -> string

val eq_command : command -> command -> bool