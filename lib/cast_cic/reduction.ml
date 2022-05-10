(** This module specifies the operational semantics *)
(* The implementation is based on a CEK machine (https://en.wikipedia.org/wiki/CEK_Machine) *)

open Ast

(** Extended AST with tagged values

    We are using this representation because otherwise we have to 
    constantly query whether a term is canonical, when reducing the stack *)
    type vterm = 
    | Var of Name.t
    | Universe of int
    | App of vterm * vterm
    | Lambda of vfun_info
    | Prod of vfun_info
    | Unknown of vterm
    | Err of vterm
    | Cast of vcast_info

    (* Values *)
    | VLambda of vfun_info * vcontext
    | VProd of vfun_info * vcontext
    | VUnknown of vterm
    | VErr of vterm
    | VCast of vcast_info
  and vfun_info = { id: Name.t; dom: vterm; body: vterm }
  and vcontext = (Name.t, vterm) Context.t
  and vcast_info = { source: vterm; target: vterm; term: vterm }
  
  (** Converts a term of the original AST into a term with tagged values *)
  (* This could probably be "smarter", checking if the terms are canonical and 
     producing a more accurate tagged term. It would probably require a context 
     as well (e.g. for closures). *)
  let rec to_vterm : term -> vterm = function
    | Var x -> Var x
    | Universe i -> Universe i
    | App (t, u) -> App (to_vterm t, to_vterm u)
    | Lambda fi -> Lambda (to_vfun_info fi)
    | Prod fi -> Prod (to_vfun_info fi)
    | Unknown t -> Unknown (to_vterm t)
    | Err t -> Err (to_vterm t)
    | Cast ci -> Cast { source=to_vterm ci.source;
                        target=to_vterm ci.target;
                        term=to_vterm ci.term }
  
  and to_vfun_info {id; dom; body} = {id; dom=to_vterm dom; body=to_vterm body}
  
  (** Converts a term of the original AST into a term with tagged values *)
  let to_vcontext (ctx : context) : vcontext = 
    Context.to_list ctx |>
    List.map (fun (k,v) -> (k, to_vterm v)) |>
    Context.of_list
  
  
  (** Converts a term with tagged values into a term of the original AST *)
  let rec of_vterm : vterm -> Ast.term = function
    | Var x -> Var x
    | Universe i -> Universe i
    | App (t, u) -> App (of_vterm t, of_vterm u)
    | Lambda fi | VLambda (fi,_) -> Lambda (of_vfun_info fi)
    | Prod fi  | VProd (fi, _) -> Prod (of_vfun_info fi)
    | Unknown t | VUnknown t -> Unknown (of_vterm t)
    | Err t  | VErr t -> Err (of_vterm t)
    | Cast ci -> Cast { source=of_vterm ci.source;
                        target=of_vterm ci.target;
                        term=of_vterm ci.term }
    | VCast ci -> Cast { source=of_vterm ci.source;
                        target=of_vterm ci.target;
                        term=of_vterm ci.term }
                        
  and of_vfun_info {id; dom; body} = {id; dom=of_vterm dom; body=of_vterm body}
  
  (** Performs substitution of a context inside a vterm.
      Values are untagged since terms in the context may not be fully reduced (see rule Prod-Prod in reduce1) *)
  let rec subst ctx : vterm -> vterm = function
    | Var y -> 
      (match Context.lookup ~key:y ~ctx with
       | None -> Var y
       | Some t -> t)
    | Universe i -> Universe i
    | App (t,u) -> App (subst ctx t, subst ctx u)
    | Lambda fi -> 
      let y = new_identifier () in
      let ctx' = Context.add ~key:fi.id ~value:(Var y) ctx in
      Lambda { id = y; dom = subst ctx fi.dom; body = subst ctx' fi.body }
    | Prod fi -> 
      let y = new_identifier () in
      let ctx' = Context.add ~key:fi.id ~value:(Var y) ctx in
      Prod { id = y; dom = subst ctx fi.dom; body = subst ctx' fi.body }
    | Unknown t | VUnknown t -> Unknown (subst ctx t)
    | Err t | VErr t -> Err (subst ctx t)
    | Cast { source; target; term=term' }
    | VCast { source; target; term=term' } -> 
      Cast { source = subst ctx source;
             target = subst ctx target;
             term = subst ctx term' }
    | VLambda (fi, ctx') -> 
      let y = new_identifier () in
      let ctx'' = Context.add ~key:fi.id ~value:(Var y) ctx' in
      Lambda { id = y; dom = subst ctx' fi.dom; body = subst ctx'' fi.body }
    | VProd (fi, ctx') -> 
      let y = new_identifier () in
      let ctx'' = Context.add ~key:fi.id ~value:(Var y) ctx' in
      Prod { id = y; dom = subst ctx' fi.dom; body = subst ctx'' fi.body }
  
  (** Checks if a term corresponds to a type *)
  let is_type : vterm -> bool = function
  | VProd _ | Universe _ -> true
  | _ -> false
  
  (** Checks if a term corresponds to a tagged value *)
  let is_value = function
  | VUnknown (VProd _) | VErr (VProd _) -> false
  | Universe _ | VLambda _ | VProd _ | VUnknown _ | VErr _ | VCast _ -> true
  | _ -> false

(** The representation of a continuation of the CEK machine *)
type continuation =
| KHole
  (* Reducing the rhs of an app *)
  | KApp_l of (vterm * vcontext * continuation)
  (* Reducing the lhs of an app *)
  | KApp_r of (vfun_info * vcontext * continuation)
  (* Reducing the domain of a lambda *)
  | KLambda of (Name.t * vterm * vcontext * continuation)
  (* Reducing the domain of a product *)
  | KProd of (Name.t * vterm * vcontext * continuation)
  (* Reducing the type of an unknown *)
  | KUnknown of (vcontext * continuation)
  (* Reducing the type of an error *)
  | KErr of (vcontext * continuation)
  (* Reducing the source of a cast *)
  | KCast_source of (vterm * vterm * vcontext * continuation)
  (* Reducing the target of a cast. Source and term are stored in the state *)
  | KCast_target of (vterm * vterm * vcontext * continuation)
  (* Reducing the term of a cast. Source and target are stored in the state *)
  | KCast_term of (vterm * vterm * vcontext * continuation)

(* Just an alias *)
type state = vterm * vcontext * continuation

exception Stuck_term

(** One step reduction of terms *)
let reduce1 (term, ctx, cont) : state =
  match term, cont with
  (* Redexes *)
    (* Delta *)
  | (Var x, _) ->
    (match Context.lookup ~key:x ~ctx with
     | Some v -> (v, ctx, cont)
     | None   -> failwith ("free identifier: " ^ Name.to_string x))
     (* Since ids are considered neutral, ie, valid terms, this should just return it back 
  instead of failing, no? *)
     (* | None   -> (term, ctx, cont) *)

    (* Beta *)
    (* Using a call-by-value approach *)
  | (u, KApp_r (fi, ctx, cont)) when is_value u ->
    let ctx' = Context.add ~key:fi.id ~value:u ctx in
    (fi.body, ctx', cont)

    (* Prod-Unk *)
  | (VUnknown (VProd (fi, ctx')), _) ->
    (VLambda ({id=fi.id; dom=fi.dom; body=Unknown fi.body}, ctx') , ctx, cont)
    
     (* Prod-Err *)
  | (VErr (VProd (fi, ctx')), _) ->
    (VLambda ({id=fi.id; dom=fi.dom; body=Err fi.body}, ctx'), ctx, cont)

    (* Down-Unk *)
  | (VUnknown (VUnknown (Universe _)), KCast_term (VUnknown (Universe _), target, _, cont)) ->
    (VUnknown target, ctx, cont)

    (* Down-Err *)
  | (VErr (VUnknown (Universe _)), KCast_term (VUnknown (Universe _), target, _, cont)) ->
    (VErr target, ctx, cont)

    (* Prod-Prod *)
  | (VLambda (term_fi, term_ctx), KCast_term (VProd (source_fi, source_ctx), VProd (target_fi, target_ctx), _, cont)) ->
    let y_id = new_identifier () in
    let y = Var y_id in
    let inner_cast = Cast { source = target_fi.dom; target = term_fi.dom; term = y} in
    let inner_body_ctx = Context.add ~key:term_fi.id ~value:inner_cast term_ctx in
    let inner_body = subst inner_body_ctx term_fi.body in
    let source_cast = Cast { source = target_fi.dom; target = source_fi.dom; term = y} in
    let body_source_ctx = Context.add ~key:source_fi.id ~value:source_cast source_ctx in
    let body_target_ctx = Context.add ~key:target_fi.id ~value:y target_ctx in
    let body = Cast { source = subst body_source_ctx source_fi.body;
                      target = subst body_target_ctx target_fi.body;
                      term   = inner_body } in
    let fi = {id=y_id; dom=target_fi.dom; body} in
    (VLambda (fi, term_ctx), ctx, cont)

    (* Univ-Univ *)
  | (t, KCast_term (Universe i, Universe j, _, cont)) 
     when is_value t && i == j -> (t, ctx, cont)

    (* Head-Err *)
  | (t, KCast_term (source, target, _, cont)) when is_value t && is_type source && is_type target ->
     (VErr target, ctx, cont)

    (* Dom-Err *)
  | (t, KCast_term (VErr (Universe _), target, _, cont)) when is_value t -> (VErr target, ctx, cont)

    (* Codom-Err *)
  | (t, KCast_term (source, (VErr (Universe _) as target), _, cont)) when is_value t && is_type source ->
     (VErr target, ctx, cont)
     
    (* Prod-Germ *)
  | (f, KCast_term ((VProd _ as source), (VUnknown (Universe i) as target), _, cont)) 
      when is_value f && not (of_vterm source |> is_germ_for_gte_level i) ->
    let middle = to_vterm (germ i HProd) in
    let inner_cast = Cast {source; target=middle; term=f} in
    let outer_cast = Cast {source=middle; target; term=inner_cast} in
    (outer_cast, ctx, cont)

    (* Up-Down *)
  | (VCast {source; target=VUnknown (Universe i); term}, KCast_term (VUnknown (Universe j), target, _, cont))
    (* Is i == j necessary or type checking ensures? *)
    when i == j && (of_vterm source |> is_germ i)  ->
    (Cast {source; target; term}, ctx, cont)

    (* TODO: Check if this can be replaced with is_germ_for_gte_level *)
    (* Size-Err Universe *)
  | (_, KCast_term (Universe j, VUnknown (Universe i), _, cont)) 
    when j >= i -> (VErr (VUnknown (Universe i)), ctx, cont)

    (* Size-Err Prod *)
    | (_, KCast_term (VProd ({id=_; dom=VUnknown (Universe j); body=Unknown (Universe k)}, _), VUnknown (Universe i), _, cont)) 
    when j == k && j > cast_universe_level i -> (VErr (VUnknown (Universe i)), ctx, cont)
  

  (* Congruence rules *)
  | (dom, KLambda (id, body, _, cont)) when is_value dom -> (VLambda ({id;dom;body}, ctx), ctx, cont)
  | (dom, KProd (id, body, _, cont)) when is_value dom -> (VProd ({id;dom;body}, ctx), ctx, cont)
  | (VLambda (fi, ctx'), KApp_l (u, _, cont)) -> (u, ctx, KApp_r (fi, ctx', cont))
  | (t, KUnknown (_, cont)) when is_value t -> (VUnknown t, ctx, cont)
  | (t, KErr (_, cont)) when is_value t -> (VErr t, ctx, cont)
  | (target, KCast_target (source, term, _, cont)) when is_value target ->
    (source, ctx, KCast_source (target, term, ctx, cont))
  | (source, KCast_source (target, term, _, cont)) when is_value source ->
    (term, ctx, KCast_term (source, target, ctx, cont))
  | (term, KCast_term (source, (VUnknown (Universe i) as target), _, cont)) 
      when (of_vterm source |> is_germ i) && is_value term -> 
    (VCast {source; target; term}, ctx, cont) 

  | (App (t, u), _) -> (t, ctx, KApp_l (u, ctx, cont))
  | (Lambda fi, _) -> (fi.dom, ctx, KLambda (fi.id, fi.body, ctx, cont))
  | (Prod fi, _) -> (fi.dom, ctx, KProd (fi.id, fi.body, ctx, cont))
  | (Unknown t, _) -> (t, ctx, KUnknown (ctx, cont))
  | (Err t, _) -> (t, ctx, KErr (ctx, cont))
  | (Cast {source; target; term}, _) -> (target, ctx, KCast_target (source, term, ctx, cont))

  | (_, _) -> raise Stuck_term

(** Transitive clousure of reduce1 with fuel *)
let rec reduce_fueled (fuel : int) ((term, _, cont) as s) : vterm =
  if fuel < 0 then failwith "not enough fuel" else
  if is_value term && cont == KHole
     then term
     else reduce_fueled (fuel-1) (reduce1 s)

(** Reduces a term in the given context *)
let reduce_in ctx t : term = 
  let t' = to_vterm t in
  let ctx' = to_vcontext ctx in
  let initial_state = (t', ctx', KHole) in
  reduce_fueled 10000 initial_state |> of_vterm

(** Reduces a term *)
let reduce : term -> term = reduce_in Context.empty

(** Fills a continuation with the given term *)
let rec fill_hole term cont =
  match cont with
  | KHole -> term
  | KApp_l (u, _, cont) -> fill_hole (App (term, u)) cont
  | KApp_r (t, _, cont) -> fill_hole (App (Lambda t, term)) cont
  | KLambda (id, body, _, cont) -> fill_hole (Lambda {id; dom = term; body}) cont
  | KProd (id, body, _, cont) -> fill_hole (Prod {id; dom = term; body}) cont
  | KUnknown (_, cont) -> fill_hole (Unknown term) cont
  | KErr (_, cont) -> fill_hole (Err term) cont
  | KCast_source (target, term', _, cont) ->
    fill_hole (Cast { source = term; target; term = term' }) cont
  | KCast_target (source, term', _, cont) ->
    fill_hole (Cast { source; target = term; term = term' }) cont
  | KCast_term (source, target, _, cont) ->
    fill_hole (Cast { source; target; term }) cont

(** One step reduction *)
let step ctx term =
  let vt = to_vterm term in
  let vctx = to_vcontext ctx in
  let s = (vt, vctx, KHole) in
  (try Ok (reduce1 s) with Stuck_term -> Error "stuck_term") |>
  Result.map (fun (t, _, cont) -> fill_hole t cont |> of_vterm)

