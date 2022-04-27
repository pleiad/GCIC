open Format
(** This module specifies the structure of the parsed AST *)

(** An abstract type for identifiers*)
module type ID = sig
  type t

  val of_string : string -> t
  val to_string : t -> string
  val ( = ) : t -> t -> bool
end

(** A string instance of the ID abstract type *)
module String_id = struct
  type t = string

  let of_string x = x
  let to_string x = x
  let ( = ) = String.equal
end

module Var_name : ID = String_id

(** Terms in GCIC *)
type term =
  | Var of Var_name.t
  | Universe of int
  | App of term * term
  | Lambda of Var_name.t * term * term
  | Prod of Var_name.t * term * term
  | Unknown of int

(** Returns the stringified version of a term *)
let rec to_string = function
  | Var x -> Var_name.to_string x
  | Universe i -> asprintf "Universe_%i" i
  | App (t, t') -> asprintf "(%s %s)" (to_string t) (to_string t')
  | Lambda (x, t, b) ->
      asprintf "lambda %s : %s. %s" (Var_name.to_string x) (to_string t)
        (to_string b)
  | Prod (x, a, b) ->
      asprintf "Prod %s : %s. %s" (Var_name.to_string x) (to_string a)
        (to_string b)
  | Unknown i -> asprintf "?_%i" i