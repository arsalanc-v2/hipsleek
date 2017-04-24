#include "xdebug.cppo"
(*
  Created 19-Feb-2006

  core pure constraints, including arithmetic and pure pointer
*)

open Globals
open VarGen
open Gen.Basic
(* open Exc.ETABLE_NFLOW *)
open Exc.GTable
module LO=Label_only.LOne
open Label

(* spec var *)
type spec_var =
  | SpecVar of (typ * ident * primed)

let sp_rm_prime v = match v with
    SpecVar (a,b,_) -> SpecVar(a,b,Unprimed)

let sp_add_prime v p = match v with
    SpecVar (a,b,_) -> SpecVar(a,b,p)

let mk_spec_var id = SpecVar (UNK,id,Unprimed)

let unknown_spec_var = mk_spec_var "__UNKNOWN"

let mk_typed_spec_var t id = SpecVar (t,id,Unprimed)

let mk_zero = mk_typed_spec_var Globals.null_type Globals.null_name 

let is_zero s = s==mk_zero

let is_zero_sem (SpecVar (_,s,_)) = (s=Globals.null_name)

let get_unprime (SpecVar(_,id,_)) = id

let view_args_map:(string,spec_var list) Hashtbl.t 
  = Hashtbl.create 10
(* immutability annotations *)
type ann = ConstAnn of heap_ann 
         | PolyAnn of spec_var
         | TempAnn of ann 
         | TempRes of (ann * ann) (* | Norm of (ann * ann) *)
         | NoAnn

(* type view_arg = SVArg of spec_var | AnnArg of ann *)

(* annotation argument type *)
type annot_arg = ImmAnn of ann

(* initial arg map: view arg or annot arg *)
type view_arg = SVArg of spec_var | AnnotArg of annot_arg

let compare_sv (SpecVar (t1, id1, pr1)) (SpecVar (t2, id2, pr2))=
  if (t1=t2)&&(pr1=pr2) then compare id1 id2
  else -1

let is_hole_spec_var sv = match sv with
  | SpecVar (_,n,_) -> n.[0] = '#'

let is_inter_deference_spec_var sv = match sv with
  | SpecVar (_,n,_) -> (
      let re = Str.regexp "^deref_f_r_" in
      Str.string_match re n 0
    )

(** An Hoa : Array whose elements are all of type typ.
     In principle, this is 1D array. To have higher 
    			diensional array, but we need to use nested arrays.
    			It seems inefficient to me; but simpler to do!
    	 *)
(* | Array of typ  *)

let is_arr_typ sv = match sv with
  | SpecVar(Array _,_,_) -> true
  | _ -> false

let is_void_typ sv = match sv with
  | SpecVar(Void,_,_) -> true
  | _ -> false

let is_self_spec_var sv = match sv with
  | SpecVar (_,n,_) -> n = self

let self_sv = mk_spec_var self 

let is_baseptr_var sv = match sv with
  | SpecVar (_,n,_) -> n = "BasePtr"

let is_res_spec_var sv = match sv with
  | SpecVar (_,n,_) -> n = res_name

let is_tup2_typ sv = match sv with
  | SpecVar (Globals.Tup2 _,_,_) -> true
  | _ -> false

let is_bag_typ sv = match sv with
  | SpecVar (BagT _,_,_) -> true
  | _ -> false

let is_bag_tup2_typ sv = match sv with
  | SpecVar (BagT t,_,_) -> (match t with | Globals.Tup2 _ -> true | _ -> false)
  | _ -> false

let is_rel_typ sv = match sv with
  | SpecVar (RelT _,_,_) -> true
  | _ -> false

let is_hprel_typ sv = match sv with
  | SpecVar (HpT,_,_) -> true
  | _ -> false

(* let is_sl_typ sv = match sv with  *)
(*   | SpecVar (SLTyp, _, _) -> true *)
(*   | _ -> false                    *)

let is_form_typ sv = match sv with
  | SpecVar (FORM, _, _) -> true
  | _ -> false

let is_otype (t : typ) : bool = match t with
  | TVar _ | Named _ -> true
  | _ -> false (* | _ -> false *) (* An Hoa *)

let is_btype (t : typ) : bool = match t with
  | Bool -> true
  | _ -> false (* | _ -> false *) (* An Hoa *)

let is_node_typ sv = match sv with
  | SpecVar (Named _,_,_) -> true
  | _ -> false

let is_hp_typ sv = match sv with
  | SpecVar (HpT,_,_) -> true
  | _ -> false

let is_var_typ sv =
  match sv with
  | SpecVar (t, _, _) -> is_type_var t
  

let is_bool_typ sv = match sv with
  | SpecVar (Bool,_,_) -> true
  | _ -> false

let is_int_typ sv = match sv with
  | SpecVar (Int,_,_) -> true
  | _ -> false

let is_num_typ sv = match sv with
  | SpecVar (NUM,_,_) -> true
  | _ -> false

let is_num_or_int_typ sv = match sv with
  | SpecVar (n,_,_) -> n==NUM || n=Int
  (* | _ -> false *)

let is_ann_typ sv = match sv with
  | SpecVar (AnnT,_,_) -> true
  | _ -> false

let is_tmp_int sv = match sv with
  | SpecVar (Int,str,_) ->  ((String.length str) > 5) && ((String.compare (String.sub str 0 5) "v_int") == 0)
  | _ -> false

let zinf_str = constinfinity

let is_inf_sv sv = match sv with
  (*| SpecVar (Int,zinf_str,_) -> true*)
  (* Above doesn't work as it matches against all integer spec vars *)
  | SpecVar (Int,"ZInfinity",_) -> true
  | _ -> false

type flow_range = int * int 

type rel_cat = 
  | RelDefn of spec_var * (string option) (* WN : extra global flow var in 2nd parameter; for non-normal flows *)
  | HPRelDefn of (spec_var * spec_var * spec_var list) (*hp name * root * arguments*)
  | HPRelLDefn of spec_var list
  | RelAssume of spec_var list
  (* | RankDecr of spec_var list *)
  (* | RankBnd of spec_var       *)


type xpure_view = {
  xpure_view_node : spec_var option;
  xpure_view_name : ident;
  xpure_view_arguments : spec_var list;
  xpure_view_remaining_branches :  (formula_label list) option;
  xpure_view_pos : loc;
  (* xpure_view_derv : bool; *)
  (* xpure_view_imm: ann; *)
  (* xpure_view_perm : cperm; (\*LDK: permission*\) *)
  (* xpure_view_arguments : CP.spec_var list; *)
  (* xpure_view_modes : mode list; *)
  (* xpure_view_coercible : bool; *)
  (* (\* if this view is generated by a coercion from another view c,  *)
  (*    then c is in xpure_view_origins. Used to avoid loopy coercions *\) *)
  (* xpure_view_origins : ident list; *)
  (* xpure_view_original : bool; *)
  (* xpure_view_lhs_case : bool; (\* to allow LHS case analysis prior to unfolding and lemma *\) *)
  (* (\* to allow LHS case analysis prior to unfolding and lemma *\) *)
  (* xpure_view_unfold_num : int; (\* to prevent infinite unfolding *\) *)
  (* (\* xpure_view_orig_fold_num : int; (\\* depth of originality for folding *\\) *\) *)
  (* (\* used to indicate a specialised view *\) *)
  (* xpure_view_pruning_conditions :  (CP.b_formula * formula_label list ) list; *)
  (* xpure_view_label : formula_label option; *)
}


type formula =
  | BForm of (b_formula * (formula_label option))
  (* | Pure_Baga of (spec_var list) *)
  (* ADDR[a,b] <==> a>0 & b>0 > a!=b *)
  (* | BagaF of (spec_var list * formula) *)
  | And of (formula * formula * loc)
  | AndList of (LO.t * formula) list
  | Or of (formula * formula * (formula_label option) * loc)
  | Not of (formula * (formula_label option) * loc)
  | Forall of (spec_var * formula * (formula_label option) * loc)
  | Exists of (spec_var * formula * (formula_label option) * loc)

and bf_annot = (bool * int * (exp list))
(* (is_linking, label, list of linking expressions in b_formula) *)

(* Boolean constraints *)
and b_formula = p_formula * (bf_annot option)

and lex_info_old = (term_ann * (exp list) * (exp list) * loc)

(* should migrate to form below *)
and lex_info = {
  lex_ann : term_ann;
  lex_exp : exp list; (* current lexicographic measures *)
  lex_fid : ident; (* name of the function LexVar belongs to *)
  lex_tmp : exp list; (* for temporary storage of measures *)
  lex_loc : loc; (* location of LexVar *)
}

and term_ann = 
  | Term                       (* definite termination *)
  | Loop of term_cex option    (* definite non-termination *)
  | MayLoop of term_cex option (* possible non-termination *)
  | Fail of term_fail          (* Failure because of invalid trans *)
  | TermU of uid               (* unknown precondition with sol *)
  | TermR of uid               (* unknown postcondition *)

and uid = {
  tu_id: int;
  tu_sid: ident;
  tu_fname: ident;
  tu_call_num: int;
  tu_args: exp list;
  tu_cond: formula; 
  tu_icond: formula;
  tu_sol: (term_ann * exp list) option; (* Term Ann. with Ranking Function *)
  tu_pos: loc;
}

and term_cex = {
  tcex_trace: tcex_cmd list; 
}

and tcex_cmd = 
  | TAssume of formula
  | TCall of loc

and term_fail =
  | TermErr_May
  | TermErr_Must

and imm_ann = 
  | PostImm of p_formula  (* unknown precondition, need to be inferred *)
  | PreImm of p_formula (* unknown postcondition, need to be inferred *)

and p_formula =
  | Frm of (spec_var * loc)
  | XPure of xpure_view
  | LexVar of lex_info
  | BConst of (bool * loc)
  | BVar of (spec_var * loc)
  | Lt of (exp * exp * loc)
  | Lte of (exp * exp * loc)
  | Gt of (exp * exp * loc)
  | Gte of (exp * exp * loc)
  | SubAnn of (exp * exp * loc)
  | Eq of (exp * exp * loc) (* these two could be arithmetic or pointer or bag or list *)
  | Neq of (exp * exp * loc)
  | EqMax of (exp * exp * exp * loc) (* first is max of second and third *)
  | EqMin of (exp * exp * exp * loc) (* first is min of second and third *)
  (* bag formulas *)
  | BagIn of (spec_var * exp * loc)
  | BagNotIn of (spec_var * exp * loc)
  | BagSub of (exp * exp * loc)
  | BagMin of (spec_var * spec_var * loc)
  | BagMax of (spec_var * spec_var * loc)
  (* var permission constraints *)
  (* denote location of variables *)
  (* do not substitute or rename here!!!! *)
  (* NOTE: currently work with Redlog only*)
  (* TO DO: filter out VarPerm before discharge*)
  (* | VarPerm of (vp_ann * (spec_var list) * loc) (*list of (primed) variables*) *)
  (* list formulas *)
  | ListIn of (exp * exp * loc)
  | ListNotIn of (exp * exp * loc)
  | ListAllN of (exp * exp * loc)
  | ListPerm of (exp * exp * loc)
  | RelForm of (spec_var * (exp list) * loc)
  | ImmRel of (p_formula * imm_ann * loc) (* RelForm * cond * pos *)
(* An Hoa: Relational formula to capture relations, for instance, s(a,b,c) or t(x+1,y+2,z+3), etc. *)

(* Expression *)
and exp =
  | Null of loc
  | Var of (spec_var * loc)
  | Level of (spec_var * loc) (*represent locklevel of a lock spec_var*)
  | IConst of (int * loc)
  | FConst of (float * loc)
  | AConst of (heap_ann * loc)
  | InfConst of (ident * loc)
  | NegInfConst of (ident * loc)
  | Tsconst of (Tree_shares.Ts.t_sh * loc)
  | Bptriple of ((spec_var * spec_var * spec_var) * loc) (*triple for bounded permissions*)
  | Tup2 of ((exp * exp) * loc) (*a pair*)
  | Add of (exp * exp * loc)
  | Subtract of (exp * exp * loc)
  | Mult of (exp * exp * loc)
  | Div of (exp * exp * loc)
  | Max of (exp * exp * loc)
  | Min of (exp * exp * loc)
  | TypeCast of (typ * exp * loc)
  (* bag expressions *)
  | Bag of (exp list * loc)
  | BagUnion of (exp list * loc)
  | BagIntersect of (exp list * loc)
  | BagDiff of (exp * exp * loc)
  (* list expressions *)
  | List of (exp list * loc)
  | ListCons of (exp * exp * loc)
  | ListHead of (exp * loc)
  | ListTail of (exp * loc)
  | ListLength of (exp * loc)
  | ListAppend of (exp list * loc)
  | ListReverse of (exp * loc)
  (* | StrConst of (string * loc) *)
  (* | StrAppend of (exp list * loc) *)
  | ArrayAt of (spec_var * (exp list) * loc)      (* An Hoa : array access *)
  | Func of (spec_var * (exp list) * loc)
  (* Template exp *)
  | Template of template

and template = {
  (* a + bx + cy + dz *)
  templ_id: spec_var;
  templ_args: exp list; (*    [x, y, z] *)
  templ_unks: exp list; (* [a, b, c, d] *)
  templ_body: exp option;
  templ_pos: loc;
}

and relation = (* for obtaining back results from Omega Calculator. Will see if it should be here *)
  | ConstRel of bool
  | BaseRel of (exp list * formula)
  | UnionRel of (relation * relation)

and constraint_rel = 
  | Unknown
  | Subsumed
  | Subsuming
  | Equal
  | Contradicting

and rounding_func = 
  | Ceil
  | Floor

and infer_rel_type =  (rel_cat * formula * formula)

                        
let get_rel_from_imm_ann p = match p with
  | PostImm f
  | PreImm  f -> f

let extr_spec_var e = match e with 
  | Var(v,_) -> v
  | _ -> x_report_error no_pos "extr_spec_var : did not encounter var" 

let rec compare_term_ann a1 a2 =
  match a1, a2 with 
  | Term, Term -> 0
  | Loop _, Loop _ -> 0
  | MayLoop _, MayLoop _ -> 0
  | Fail f1, Fail f2 -> compare_term_fail f1 f2
  | TermU u1, TermU u2 -> compare_uid u1 u2
  | TermR u1, TermR u2 -> compare_uid u1 u2
  | _ -> 1

and compare_uid u1 u2 = 
  let cid = compare u1.tu_id u2.tu_id in
  if cid != 0 then cid
  else String.compare u1.tu_sid u2.tu_sid

and compare_term_fail f1 f2 = 
  match f1, f2 with
  | TermErr_May, TermErr_May -> 0
  | TermErr_Must, TermErr_Must -> 0
  | _ -> 1

let eq_term_ann a1 a2 = 
  compare_term_ann a1 a2 == 0

let eq_uid u1 u2 = 
  compare_uid u1 u2 == 0

let rec is_MayLoop ann = 
  match ann with
  | MayLoop _ -> true
  | TermU uid -> begin
      match uid.tu_sol with
      | None -> false
      | Some (s, _) -> is_MayLoop s
    end
  | _ -> false 

let rec is_Loop ann = 
  match ann with
  | Loop _ -> true
  | TermU uid -> is_Loop_uid uid
  | _ -> false

and is_Loop_uid uid = 
  match uid.tu_sol with
  | None -> false
  | Some (s, _) -> is_Loop s

let rec is_Term ann = 
  match ann with
  | Term -> true
  | TermU uid -> begin
      match uid.tu_sol with
      | None -> false
      | Some (s, _) -> is_Term s
    end
  | _ -> false

let is_TermU ann =
  match ann with
  | TermU _ -> true
  | _ -> false

let is_unknown_term_ann ann =
  match ann with
  | TermU uid 
  | TermR uid -> begin
      match uid.tu_sol with
      | None -> true
      | _ -> false
    end
  | _ -> false

let add_args_uid uid args = 
  {uid with tu_args = uid.tu_args @ args; }

let add_args_term_ann ann args = 
  match ann with
  | TermU uid -> TermU (add_args_uid uid args)
  | TermR uid -> TermR (add_args_uid uid args)
  | _ -> ann

let rec map_term_ann f_f f_e ann = 
  match ann with
  | TermU uid -> TermU (map_ann_uid f_f f_e uid)
  | TermR uid -> TermR (map_ann_uid f_f f_e uid)
  | _ -> ann

and map_ann_uid f_f f_e uid = 
  { uid with
    tu_args = List.map f_e uid.tu_args;
    tu_cond = f_f uid.tu_cond;
    tu_icond = f_f uid.tu_icond;
    tu_sol = map_opt (fun (ann, el) ->
        (map_term_ann f_f f_e ann),
        List.map f_e el) uid.tu_sol; }

let is_False cp = match cp with
  | BForm (p,_) ->
    begin
      match p with
      | (BConst (b,_),_) -> not(b)
      | _ -> false
    end
  | _ -> false

let is_True cp = match cp with
  | BForm (p,_) -> 
    begin
      match p with
      | (BConst (b,_),_) -> b
      | _ -> false
    end
  | _ -> false

let is_Prim cp = match cp with
  | BForm (p,_) -> true
  | _ -> false

let rec is_forall p = match p with
  | Forall _ -> true
  | And (p1,p2,_) -> is_forall p1 || is_forall p2
  | AndList ps -> List.exists (fun (_, p1) -> is_forall p1) ps
  | _ -> false

let exp_to_spec_var e =
  match e with
  | Var (sv, _) -> sv
  | _ -> report_error no_pos ("Not a spec var\n")

(* Slicing Utils *)
(* let linking_var_tbl = ref (Hashtbl.create 10) *)
let linking_var_tbl = ref []

let rec set_il_formula f il =
  (* if not !Globals.do_slicing then f *)
  if !Globals.dis_slc_ann then f
  else match f with
    | BForm (bf, lbl) -> BForm (set_il_b_formula bf il, lbl)
    | _ -> f

and set_il_b_formula bf il =
  let (pf, o_il) = bf in
  match o_il with
  | None -> (pf, il)
  | Some (_, _, l_exp) ->
    match il with
    | None -> bf
    | Some (b, i, le) -> (pf, Some (b, i, le@l_exp))

let print_b_formula = ref (fun (c:b_formula) -> "cpure printer has not been initialized")
let print_p_formula = ref (fun (c:p_formula) -> "cpure printer has not been initialized")
let print_exp = ref (fun (c:exp) -> "cpure printer has not been initialized")
let print_formula = ref (fun (c:formula) -> "cpure printer has not been initialized")
let print_svl = ref (fun (c:spec_var list) -> "cpure printer has not been initialized")
let print_sv = ref (fun (c:spec_var) -> "cpure printer has not been initialized")
let print_annot_arg = ref (fun (c:annot_arg) -> "cpure printer has not been initialized")
let print_term_ann = ref (fun (t:term_ann) -> "cpure printer has not been initialized")
let tp_imply = ref (fun (lhs:formula) (rhs:formula) -> ((failwith "tp_imply not yet initialized"):bool))

let print_view_arg v= match v with
  | SVArg sv -> "SVArg " ^ (!print_sv sv)
  | AnnotArg asv -> "AnnotArg " ^ (!print_annot_arg asv)

let print_rel_cat rel_cat = match rel_cat with
  | RelDefn (v,vs) -> "RELDEFN " ^ (!print_sv v) ^(match vs with None -> "" | Some t -> (* pr_pair string_of_int string_of_int *) "("^t^")")
  | HPRelDefn (v,r,args) -> "HP_RELDEFN " ^ (!print_sv v)
  | HPRelLDefn vs -> "HP_REL_L_DEFN " ^ (!print_svl vs)
  | RelAssume v -> "RELASS " ^ (!print_svl v)
  (* | RankDecr vs -> "RANKDEC " ^ (!print_svl vs) *)
  (* | RankBnd v -> "RANKBND " ^ (!print_sv v)     *)

let print_lhs_rhs (cat,l,r) = (print_rel_cat cat)^": ("^(!print_formula l)^") --> "^(!print_formula r)

let print_only_lhs_rhs (l,r) = "("^(!print_formula l)^") --> "^(!print_formula r)

let string_of_infer_rel = print_lhs_rhs


let full_perm_var_name = "Anon_full_perm"

let rec isConstTrue (p:formula) = match p with
  | BForm ((BConst (true, pos), _),_) -> true
  | AndList b -> all_l_snd isConstTrue b
  | Exists (_,p1,_,_) -> isConstTrue p1
  | Forall (_,p1,_,_) -> isConstTrue p1
  | _ -> false

and isConstFalse (p:formula) =
  match p with
  | BForm ((BConst (false, pos),_),_) -> true
  | AndList b -> exists_l_snd isConstFalse b
  | _ -> false

and mkAnd_dumb f1 f2 pos = 
  if (isConstFalse f1) then f1
  else if (isConstTrue f1) then f2
  else if (isConstFalse f2) then f2
  else if (isConstTrue f2) then f1
  else And (f1, f2, pos)

let mkSubAnn a1 a2 = BForm ((SubAnn(a1,a2,no_pos),None),None)

module Exp_Pure =
struct 
  type e = formula
  let comb x y = mkAnd_dumb x y no_pos (*And (x,y,no_pos)*)
  let string_of = !print_formula
  let ref_string_of = print_formula
end;;

module Label_Pure = LabelExpr(LO)(Exp_Pure);; 

let is_self_var = function
  | Var (x,_) -> is_self_spec_var x
  | _ -> false

let name_of_rel_form r = 
  match r with 
  | BForm ((RelForm (name,args,_),_),_) -> name
  | _ -> raise Not_found

let is_res_var = function
  | Var (x,_) -> is_res_spec_var x
  | _ -> false

let is_bool_res_var = function
  | Var (x,_) -> is_bool_typ x (* && is_res_spec_var x *)
  | _ -> false

(* let type_of_spec_var (sv : spec_var) = match sv with *)
(*   | SpecVar (t, _, p) -> t  *)

let primed_of_spec_var (sv : spec_var) : primed = match sv with
  | SpecVar (_, _, p) -> p 

let name_of_spec_var (sv : spec_var) : ident = match sv with
  | SpecVar (_, v, _) -> v

let primed_ident_of_spec_var (sv : spec_var) = match sv with
  | SpecVar (_, v, p) -> (v,p)

let name_of_sv (sv : spec_var) : ident = match sv with
  | SpecVar (_, v, _) -> v

let typ_of_sv (sv : spec_var)  = match sv with
  | SpecVar (t, v, _) -> t

let rename_spec_var (sv: spec_var) new_name = 
  match sv with
  | SpecVar (t, _, p) -> SpecVar (t, new_name, p)

let flted_rgx = Str.regexp "flted_[1-9][0-9]*_[1-9][0-9]*" 

let check_is_field x =
  Str.string_match flted_rgx x 0 

let check_is_field_sv x =
  check_is_field (name_of_spec_var x)

let exp_to_name_spec_var e = 
  match e with
  | Var(sv,_) -> name_of_spec_var sv 
  | Null _ -> "null_node"
  | IConst(i,_) -> (string_of_int i)
  | _ -> ""

let full_name_of_spec_var (sv : spec_var) : ident = match sv with
  | SpecVar (_, v, p) -> if (p==Primed) then (v^"\'") else v

let type_of_spec_var (sv : spec_var) : typ =
  match sv with
  | SpecVar (t, _, _) -> t

let type_of_spec_var_list (sv : spec_var list) : typ list = List.map type_of_spec_var sv

let is_float_var (sv : spec_var) : bool = is_float_type (type_of_spec_var sv)

(* RelT, uH_t *)
let is_rel_var (sv : spec_var) : bool = is_RelT (type_of_spec_var sv)

let is_rel_all_var (sv : spec_var) : bool = 
  let t = (type_of_spec_var sv) in
  is_RelT(t) || is_HpT(t)

let is_func_var (sv: spec_var): bool = is_FuncT (type_of_spec_var sv)

let is_hp_rel_var (sv : spec_var) : bool = is_HpT (type_of_spec_var sv)

let is_primed (sv : spec_var) : bool = match sv with
  | SpecVar (_, _, p) -> p = Primed

let is_unprimed (sv : spec_var) : bool = match sv with
  | SpecVar (_, _, p) -> p = Unprimed

let to_primed (sv : spec_var) : spec_var = match sv with
  | SpecVar (t, v, _) -> SpecVar (t, v, Primed)

let to_unprimed (sv : spec_var) : spec_var = match sv with
  | SpecVar (t, v, _) -> SpecVar (t, v, Unprimed)

let to_int_var (sv : spec_var) : spec_var = match sv with
  | SpecVar (_, v, p) -> SpecVar (Int, v, p)

(* name prefix for int const *)
let const_prefix = "__CONST_Int_"

let imm_const_prefix = "__CONST_Imm_"

let const_prefix_len = String.length(const_prefix)

(* is string a int const, n is prefix length *)
let is_int_str_aux (n:int) (s:string) : bool =
  if (n<= const_prefix_len) then false
  else 
    let p = String.sub s 0 const_prefix_len in
    if (p=const_prefix) then true
    else false

let ident_of_spec_var (sv: spec_var) = match sv with
  | SpecVar (t, v, _) -> v 

let string_of_spec_var ?(print_typ=false) (sv: spec_var) = match sv with
  | SpecVar (t, v, p) -> 
    if print_typ then
      if p==Primed then (v^"':"^(string_of_typ t)) 
      else (v^":"^(string_of_typ t))
    else if p==Primed then (v^"'") else v

let string_of_typed_spec_var (sv: spec_var) = 
  string_of_spec_var ~print_typ:true sv

(* match sv with *)
(*   | SpecVar (t, v, _) -> v ^ (if is_primed sv then "#'" else "")^":"^(string_of_typ t) *)

(* let string_of_typed_spec_var x =  string_of_spec_var_type x *)

let string_of_ann a = match a with
  | ConstAnn h -> string_of_heap_ann h
  | PolyAnn v -> "PolyAnn"
  | TempAnn v -> "TempAnn"
  | TempRes _ -> "TempRes"
  | NoAnn -> "@[NOANN]"

let rec string_of_imm_helper imm = 
  match imm with
  | ConstAnn(Accs) -> "@A"
  | ConstAnn(Imm) -> "@I"
  | ConstAnn(Lend) -> "@L"
  | ConstAnn(Mutable) -> "@M"
  | TempAnn(t) -> "@[" ^ (string_of_imm_helper t) ^ "]"
  | TempRes(l,r) -> "@[" ^ (string_of_imm_helper l) ^ ", " ^ (string_of_imm_helper r) ^ "]"
  | PolyAnn(v) -> "@" ^ (string_of_spec_var v)
  | NoAnn -> "@[NOANN]"

let rec string_of_imm imm = 
  if not !print_ann then ""
  else string_of_imm_helper imm

let rec string_of_imm_ann imm = 
  match imm with
  | PolyAnn(v) -> string_of_spec_var v
  | _             -> string_of_imm_helper imm

let rec string_of_typed_imm_ann imm = 
  match imm with
  | PolyAnn(v) -> string_of_typed_spec_var v
  | _             -> string_of_imm_helper imm

let string_of_annot_arg ann = 
  match ann with
  | ImmAnn imm -> string_of_imm_ann imm

let string_of_annot_arg_list ann_list = 
  pr_list string_of_annot_arg ann_list

(* pretty printing for a spec_var list *)
let rec string_of_spec_var_list_noparen l = match l with 
  | [] -> ""
  | h::[] -> string_of_spec_var h 
  | h::t -> (string_of_spec_var h) ^ "," ^ (string_of_spec_var_list_noparen t)
;;

let string_of_spec_var_list l = "["^(string_of_spec_var_list_noparen l)^"]" ;;

(* pretty printing for a spec_var list *)
let rec string_of_typed_spec_var_list_noparen l = match l with 
  | [] -> ""
  | h::[] -> string_of_typed_spec_var h 
  | h::t -> (string_of_typed_spec_var h) ^ "," ^ (string_of_typed_spec_var_list_noparen t)
;;

let string_of_typed_spec_var_list l = "["^(string_of_typed_spec_var_list_noparen l)^"]" ;;

let string_of_spec_var_arg l = "<"^(string_of_spec_var_list_noparen l)^">" ;;

let string_of_xpure_view xp = match xp with
    {
      xpure_view_node = root ;
      xpure_view_name = vname;
      xpure_view_arguments = args;
    } ->
    let pr = string_of_spec_var in
    let rn,args_s = match root with
      | None -> ("", pr_list_round pr args)
      | Some v -> ((pr v)^"::", pr_list_angle pr args)
    in
    "XPURE("^rn^vname^args_s^")"

(* get int value if it is an int_const *)
let get_int_const (s:string) : int option =
  let n=String.length s in
  if (is_int_str_aux n s) then
    let c = String.sub s const_prefix_len (n-const_prefix_len) in
    try Some (int_of_string c)
    with _ -> None (* should not be possible *)
  else None

(* check if a string denotes an int_const *)
let is_int_str (s:string) : bool =
  let n=String.length s in
  is_int_str_aux n s

(* check if a string is a null const *)
let is_null_str (s:string) : bool = 
  (s==Globals.null_name)


(* is string a constant?  *)
let is_const (s:spec_var) : bool =
  let n = name_of_spec_var s in
  (is_zero s (* is_null_str n *)) || (is_int_str n)

(* is string a constant?  *)
let is_null_const (s:spec_var) : bool =
  is_zero s
(* let n = name_of_spec_var s in *)
(* (is_null_str n)  *)

let is_null_const (s:spec_var) : bool =
  Debug.no_1 "is_null_const" !print_sv string_of_bool
    is_null_const s

(* is string a constant?  *)
let is_null_const_exp (e:exp) : bool = match e with
  | Var(v,_) -> is_null_const v
  | _ -> false

(* is string an int constant?  *)
let is_int_const (s:spec_var) : bool =
  let n = name_of_spec_var s in
  (is_int_str n)

let conv_var_to_exp (v:spec_var) :exp =
  if (is_zero_sem v)
  (* full_name_of_spec_var v=Globals.null_name) *) then (Null no_pos)
  else match get_int_const (name_of_spec_var v) with
    | Some i -> IConst(i,no_pos)
    | None -> Var(v,no_pos)

(* let conv_var_to_exp_debug (v:spec_var) :exp = *)
(*  Debug.no_1 "conv_var_to_exp" (full_name_of_spec_var) (!print_exp) conv_var_to_exp v *)

(* is exp a var  *)
let is_var (f:exp) = match f with
  | Var _ -> true
  | _ -> false

(* is exp a var or const *)
let is_const_or_var (f:exp) = match f with
  | Var _ -> true
  | IConst _ -> true
  | FConst _ -> true
  | _ -> false

(* is exp a const *)
let is_const_exp (f:exp) = match f with
  | IConst _ -> true
  | FConst _ -> true
  | _ -> false

let is_const_or_tmp (f:exp) = match f with
  | IConst _ -> true
  | FConst _ -> true
  | Var(sv,_) -> is_tmp_int sv
  | _ -> false

(* is exp an infinity const *)
let is_inf (f:exp) = match f with
  | InfConst  _  
  | NegInfConst _ -> true
  | Var(sv,_) -> is_inf_sv sv
  | _ -> false

let rec contains_inf (f:exp) = match f with
  | NegInfConst _ 
  | InfConst  _ -> true
  | Var(sv,_) -> is_inf_sv sv
  | Add (e1, e2, _)
  | Subtract (e1, e2, _)
  | Mult (e1, e2, _)
  | Max (e1, e2, _)
  | Min (e1, e2, _)
  | Div (e1, e2, _)
  | ListCons (e1, e2, _)
  | BagDiff (e1, e2, _) -> (contains_inf e1) || (contains_inf e2)
  | ListHead (e, _)
  | ListLength (e, _)
  | ListTail (e, _)
  | ListReverse (e, _) -> (contains_inf  e)
  | _ -> false

let rec contains_exists (f:formula) : bool =  match f with
  | BForm _ -> false
  | Or (f1,f2,_,_)
  | And (f1,f2, _) -> (contains_exists f1) || (contains_exists f2)
  | Not(f1,_,_)
  | Forall (_ ,f1,_,_) -> (contains_exists f1)
  | AndList l -> exists_l_snd contains_exists l
  | Exists _ -> true

let get_var_opt (e:exp) =
  match e with
  | Var (v,_) -> Some v
  | _ -> None

let get_var (e:exp) =
  match e with
  | Var (v,_) -> v
  | _ -> report_error no_pos "[cpure.ml] get_var: expecting Var"

let get_var_opt (e:exp) =
  match e with 
  | Var (v, _) -> Some v
  | _ -> None

let filter_vars lv =
  List.fold_left (fun a c -> match c with
      | Var (v,_)-> v::a
      | _ -> a) [] lv

let rec exp_contains_spec_var (e : exp) : bool =
  match e with
  | Var (SpecVar (t, _, _), _) -> true
  | Add (e1, e2, _)
  | Subtract (e1, e2, _)
  | Mult (e1, e2, _)
  | Max (e1, e2, _)
  | Min (e1, e2, _)
  | Div (e1, e2, _)
  | ListCons (e1, e2, _)
  | BagDiff (e1, e2, _) -> (exp_contains_spec_var e1) || (exp_contains_spec_var e2)
  | ListHead (e, _)
  | ListLength (e, _)
  | ListTail (e, _)
  | ListReverse (e, _) -> (exp_contains_spec_var e)
  | List (el, _)
  | ListAppend (el, _)
  | Bag (el, _)
  | BagUnion (el, _)
  | BagIntersect (el, _) -> List.fold_left (fun a b -> a || (exp_contains_spec_var b)) false el
  | ArrayAt _ -> true
  | _ -> false





let eq_spec_var_rec (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (_, v1, p1), SpecVar (_, v2, p2)) ->
    (* translation has ensured well-typedness.
       We need only to compare names and primedness *)
    ((String.compare v1 v2 = 0) || (String.compare ("REC" ^ v1) v2 = 0)) && (p1 = p2)

let eq_spec_var1 (sv1: spec_var) (sv2: spec_var) = match (sv1, sv2) with
  | (SpecVar (_, v1, p1), SpecVar (_, v2, p2)) ->
    let reg = Str.regexp "_.*" in
    (Str.global_replace reg "" v1) = (Str.global_replace reg "" v2) && p1 = p2

let eq_spec_var (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (_, v1, p1), SpecVar (_, v2, p2)) ->
    (* translation has ensured well-typedness.
       We need only to compare names and primedness *)
     (String.compare v1 v2 = 0) && (p1 = p2)
                                     
let rec check_eq_exp e1 e2 =
  match e1, e2 with
  | IConst (i1,_), IConst (i2,_) -> i1=i2
  | Var (v1,_), Var (v2,_) -> eq_spec_var v1 v2
  | Add (ne11,ne12,_), Add (ne21,ne22,_) ->
     ((check_eq_exp ne11 ne21) && (check_eq_exp ne12 ne22))||((check_eq_exp ne11 ne22) && (check_eq_exp ne12 ne21))
  | _,_ -> false
;;


                                    
let eq_ident_var (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (_, v1, p1), SpecVar (_, v2, p2)) ->
    (* translation has ensured well-typedness.
       We need only to compare names and primedness *)
    (String.compare v1 v2 = 0) 

let overlap_svl = Gen.BList.overlap_eq eq_spec_var

(* let eq_spec_var (sv1 : spec_var) (sv2 : spec_var) =  *)
(*   let pr = !print_sv in *)
(*   Debug.no_2 "eq_spec_var" pr pr string_of_bool eq_spec_var (sv1 : spec_var) (sv2 : spec_var) *)

let eq_spec_var_unp (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (_, v1, p1), SpecVar (_, v2, p2)) ->
    (* translation has ensured well-typedness.
       We need only to compare names and primedness *)
    (String.compare v1 v2 = 0) 

let eq_typed_spec_var (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) ->
    (t1 = t2) && (String.compare v1 v2 = 0) && (p1 = p2)

let compare_spec_var (sv1 : spec_var) (sv2 : spec_var) = 
  match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) -> String.compare v1 v2

let eq_ann (a1 :  ann) (a2 : ann) : bool =
  match a1, a2 with
  | ConstAnn ha1, ConstAnn ha2 -> ha1 == ha2
  | PolyAnn sv1, PolyAnn sv2 -> eq_spec_var sv1 sv2
  | _ -> false

(* andreeac TODOIMM use wrapper below, use emap for spec eq *)
let eq_ann_list (a1 :  ann list) (a2 : ann list) : bool =
  List.fold_left (fun acc (a1,a2) -> acc &&(eq_ann a1 a2)) true (List.combine a1 a2)

let rec eq_spec_var_order_list l1 l2=
  match l1,l2 with
  |[],[] -> true
  | v1::ls1,v2::ls2 ->
    if eq_spec_var v1 v2 then
      eq_spec_var_order_list ls1 ls2
    else false
  | _ -> false

let rm_lst l2 v1 =
  let rec aux l2 =
    match l2 with
    | [] -> failwith "rm_lst : not found"
    | v2::l2 -> 
      if eq_spec_var v1 v2 then l2
      else v2::(aux l2)
  in aux l2

let sub_spec_var_list l1 l2 =
  let rec aux l1 l2 =
    match l1 with
    | [] -> true
    | v1::l1 -> 
      try 
        aux l1 (rm_lst l2 v1)
      with _ -> false
  in aux l1 l2

let sub_spec_var_list l1 l2 =
  Debug.no_2 "sub_spec_var_list" !print_svl !print_svl string_of_bool sub_spec_var_list l1 l2

let eq_spec_var_nop (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) ->
    (* translation has ensured well-typedness.
       		   We need only to compare names and primedness *)
    v1 = v2

let eq_spec_var_x (sv1 : spec_var) (sv2 : spec_var) =
  (* ignore primedness *)
  match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) -> t1 = t2 && v1 = v2

let eq_spec_var_ident (sv1 : spec_var) (sv2 : spec_var) = 
  eq_spec_var_unp sv1 sv2
(* match (sv1, sv2) with *)
(* | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) -> *)
(*           (\* We need only to compare names  of permission variables*\) *)
(*           v1 = v2 *)

let eq_pair_spec_var ((sv11 : spec_var), sv12) ((sv21 : spec_var),sv22) =
  (eq_spec_var_x sv11 sv21 && eq_spec_var_x sv12 sv22) ||
  (eq_spec_var_x sv11 sv22 && eq_spec_var_x sv12 sv21)

let eq_xpure_view_x xp1 xp2=
  let rec check_eq_order_spec_var_list svl1 svl2=
    match svl1,svl2 with
    | [],[] -> true
    | sv1::tl1,sv2::tl2 ->
      if eq_spec_var sv1 sv2 then
        check_eq_order_spec_var_list tl1 tl2
      else false
    | _ -> false
  in
  if String.compare xp1.xpure_view_name xp1.xpure_view_name = 0 then
    match xp1.xpure_view_node,xp1.xpure_view_node with
    | None,None -> check_eq_order_spec_var_list xp1.xpure_view_arguments xp2.xpure_view_arguments
    | Some r1,Some r2 -> check_eq_order_spec_var_list (r1::xp1.xpure_view_arguments) (r2::xp2.xpure_view_arguments)
    | _ -> false
  else false
let eq_xpure_view xp1 xp2=
  let pr1=string_of_xpure_view in
  Debug.no_2 "eq_xpure_view" pr1 pr1 string_of_bool
    (fun _ _ -> eq_xpure_view_x xp1 xp2) xp1 xp2

let remove_dups_svl vl = Gen.BList.remove_dups_eq eq_spec_var vl

let remove_dups_exp_lst elst = Gen.BList.remove_dups_eq check_eq_exp elst


let remove_dups_svl_stable vl = Gen.BList.remove_dups_eq_stable eq_spec_var vl

let diff_svl vl rl = Gen.BList.difference_eq eq_spec_var vl rl

let diff_svl_ident vl rl = Gen.BList.difference_eq eq_ident_var vl rl

let mem_svl1 v rl = Gen.BList.mem_eq eq_spec_var1 v rl

let mem_svl v rl = Gen.BList.mem_eq eq_spec_var v rl

(*LDK: check constant TRUE conjuncts of equalities, i.e. v=v *)
let rec is_true_conj_eq (f1:formula) : bool = match f1 with
  | BForm (b1,_) ->
    (match b1 with
     | Eq (e1,e2,_) , _ ->
       (match e1,e2 with
        | Var (v1,_), Var (v2,_)->
          let b1 = eq_spec_var v1 v2 in
          b1
        | _ -> false)
     | BConst (true, pos), _ -> true
     | _ -> false
    )
  | AndList b-> all_l_snd is_true_conj_eq b
  | _ -> false

(*LDK: remove duplicated conjuncts of equalities*)
let remove_true_conj_eq (cnjlist:formula list):formula list =
  List.filter (fun x -> not (is_true_conj_eq x)) cnjlist

(*LDK: check duplicated conjuncts of equalities*)
(*let is_dupl_conj_eq (f1:formula) (f2:formula) : bool =
  match f1,f2 with
    | BForm (b1,_),BForm (b2,_) ->
        (match b1,b2 with
          | (Eq (e11,e12,_), _) , (Eq (e21,e22,_) , _) ->
              (match e11,e12,e21,e22 with
                | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)-> 
                    let b1 = eq_spec_var v11 v21 in
                    let b2 = eq_spec_var v12 v22 in
                    let b3 = eq_spec_var v11 v22 in
                    let b4 = eq_spec_var v12 v21 in
                    (b1&&b2)||(b3&&b4)
                | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)-> 
                    let b1 = eq_spec_var v11 v21 in
                    let b2 = (v12= v22) in
                    b1&&b2
                | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)-> 
                    let b1 = (v11=v21) in
                    let b2 = eq_spec_var v12 v22 in
                    b1&b2
                | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)-> 
                    let b1 = eq_spec_var v11 v21 in
                    let b2 = (v12= v22) in
                    b1&&b2
                | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)-> 
                    let b1 = (v11=v21) in
                    let b2 = eq_spec_var v12 v22 in
                    b1&b2
                | _ -> false)
          | _ -> false
        )
    | _ -> false*)

let is_dupl_conj_diseq (f1:formula) (f2:formula) : bool =
  match f1,f2 with
  | BForm (b1,_),BForm (b2,_) ->
    (match b1,b2 with
     | (Neq (e11,e12,_), _) , (Neq (e21,e22,_) , _) ->
       (match e11,e12,e21,e22 with
        | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)-> 
          let b1 = eq_spec_var v11 v21 in
          let b2 = eq_spec_var v12 v22 in
          let b3 = eq_spec_var v11 v22 in
          let b4 = eq_spec_var v12 v21 in
          (b1&&b2)||(b3&&b4)
        | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)-> 
          let b1 = eq_spec_var v11 v21 in
          let b2 = (v12= v22) in
          b1&&b2
        | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)-> 
          let b1 = (v11=v21) in
          let b2 = eq_spec_var v12 v22 in
          b1&&b2
        | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)-> 
          let b1 = eq_spec_var v11 v21 in
          let b2 = (v12= v22) in
          b1&&b2
        | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)-> 
          let b1 = (v11=v21) in
          let b2 = eq_spec_var v12 v22 in
          b1&&b2
        | _ -> false)
     | _ -> false
    )
  | _ -> false

(* (\*LDK: check duplicated conjuncts of equalities*\) *)
(* let is_dupl_conj_lt (f1:formula) (f2:formula) : bool = *)
(*   match f1,f2 with *)
(*     | BForm (b1,_),BForm (b2,_) -> *)
(*         (match b1,b2 with *)
(*           | (Lt (e11,e12,_), _) , (Lt (e21,e22,_) , _) -> *)
(*               (match e11,e12,e21,e22 with *)
(*                 | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     (b1&&b2) *)
(*                 | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | _ -> false) *)
(*           | _ -> false *)
(*         ) *)
(*     | _ -> false *)

(* (\*LDK: check duplicated conjuncts*\) *)
(* let is_dupl_conj_lte (f1:formula) (f2:formula) : bool = *)
(*   match f1,f2 with *)
(*     | BForm (b1,_),BForm (b2,_) -> *)
(*         (match b1,b2 with *)
(*           | (Lte (e11,e12,_), _) , (Lte (e21,e22,_) , _) -> *)
(*               (match e11,e12,e21,e22 with *)
(*                 | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     (b1&&b2) *)
(*                 | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | _ -> false) *)
(*           | _ -> false *)
(*         ) *)
(*     | _ -> false *)

(* (\*LDK: check duplicated conjuncts*\) *)
(* let is_dupl_conj_gt (f1:formula) (f2:formula) : bool = *)
(*   match f1,f2 with *)
(*     | BForm (b1,_),BForm (b2,_) -> *)
(*         (match b1,b2 with *)
(*           | (Gt (e11,e12,_), _) , (Gt (e21,e22,_) , _) -> *)
(*               (match e11,e12,e21,e22 with *)
(*                 | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     (b1&&b2) *)
(*                 | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | _ -> false) *)
(*           | _ -> false *)
(*         ) *)
(*     | _ -> false *)

(*LDK: check duplicated conjuncts*)
(* let is_dupl_conj_gte (f1:formula) (f2:formula) : bool = *)
(*   match f1,f2 with *)
(*     | BForm (b1,_),BForm (b2,_) -> *)
(*         (match b1,b2 with *)
(*           | (Gte (e11,e12,_), _) , (Gte (e21,e22,_) , _) -> *)
(*               (match e11,e12,e21,e22 with *)
(*                 | Var (v11,_),Var (v12,_),Var (v21,_),Var (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     (b1&&b2) *)
(*                 | Var (v11,_),IConst (v12,_),Var (v21,_),IConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | IConst (v11,_),Var (v12,_),IConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | Var (v11,_),FConst (v12,_),Var (v21,_),FConst (v22,_)->  *)
(*                     let b1 = eq_spec_var v11 v21 in *)
(*                     let b2 = (v12= v22) in *)
(*                     b1&&b2 *)
(*                 | FConst (v11,_),Var (v12,_),FConst (v21,_),Var (v22,_)->  *)
(*                     let b1 = (v11=v21) in *)
(*                     let b2 = eq_spec_var v12 v22 in *)
(*                     b1&b2 *)
(*                 | _ -> false) *)
(*           | _ -> false *)
(*         ) *)
(*     | _ -> false *)

(*LDK: remove duplicated conjuncts of equalities*)

(* let rec helper ls = *)
(* match ls with *)
(*   | [] -> ls *)
(*   | x::xs -> *)
(*       let b = is_dupl_conj_eq *)
(* in *)
(* helper cnjlist *)

(* TODO: determine correct type of an exp *)
let rec get_exp_type (e : exp) : typ =
  match e with
  | Null _ -> Named ""
  | Var (SpecVar (t, _, _), _) -> t
  | Level _ -> Globals.level_data_typ
  | IConst _ -> Int
  | InfConst _ -> Int
  | NegInfConst _ -> Int
  | FConst _ -> Float
  | AConst _ -> AnnT
  | Tsconst _ -> Tree_sh
  | Tup2  ((e1,e2),_) -> Globals.Tup2 (get_exp_type e1,get_exp_type e2)
  | Bptriple  _ -> Bptyp
  | Add (e1, e2, _) | Subtract (e1, e2, _) | Mult (e1, e2, _)
  | Max (e1, e2, _) | Min (e1, e2, _) ->
    begin
      match get_exp_type e1, get_exp_type e2 with
      | Int, Int -> Int
      | AnnT, AnnT -> AnnT
      | _ -> Float
    end
  | Div _ -> Float
  | TypeCast (t, _, _) -> t
  | ListHead _ | ListLength _ -> Int
  | Bag _ | BagUnion _ | BagIntersect _ | BagDiff _ ->  ((Globals.BagT Globals.Int))  (* Globals.Bag *)
  | List _ | ListCons _ | ListTail _ | ListAppend _ | ListReverse _ -> Globals.List Globals.Int
  | Func _ -> Int
  | ArrayAt (SpecVar (t, a, _), _, _) -> begin
      (* Type of a[i] is the type of the element of array a *)
      match t with
      | Array (et,_) -> et
      | _ -> let () = failwith ("Cpure.get_exp_type : " ^ a ^ " is not an array variable") in Named "" 
    end
  | Template _ -> Int

let get_exp_type (e : exp) : typ =
  Debug.no_1 "get_exp_type" !print_exp string_of_typ get_exp_type e

(* *GLOBAL_VAR* substitutions list, used by omega.ml and ocparser.mly
 * moved here from ocparser.mly *)
let omega_subst_lst = ref ([]: (string*string*typ) list)


(* type constants *)
let print_subs () = pr_list (pr_pair !print_sv !print_sv)
let do_with_check msg prv_call (pe : formula) : 'a option =
  try
    Some (prv_call pe)
  with Illegal_Prover_Format s -> 
    begin
      if not(msg="") then 
        begin
          print_endline_quiet ("\nWARNING : Illegal_Prover_Format for "^msg^" :"^s);
          print_endline_quiet ("WARNING : Formula :"^(!print_formula pe));
        end;
      None
    end

let do_with_check2 msg prv_call (ante : formula) (conseq : formula) : 'a option =
  try
    Some (prv_call ante conseq)
  with Illegal_Prover_Format s -> 
    begin
      if not(msg="") then 
        begin
          print_endline_quiet ("\nWARNING : Illegal_Prover_Format for "^msg^" :"^s);
          print_endline_quiet ("WARNING : Ante :"^(!print_formula ante));
          print_endline_quiet ("WARNING : Conseq :"^(!print_formula conseq));
        end;
      None
    end

let do_with_check_default msg prv_call (pe : formula) (df:'a) : 'a =
  match (do_with_check msg prv_call pe) with
  | Some r -> r
  | None -> df 
(* use a default answer if there is prover format error *)

let bool_type = Bool

let int_type = Int

let ann_type = AnnT

let float_type = Float

let void_type = Void

let bag_type = BagT Int

(* free variables *)

let null_var = mk_zero
(* SpecVar (Named "", null_name, Unprimed) *)

let flow_var = SpecVar ((Int), flow , Unprimed)

let full_name_of_spec_var (sv : spec_var) : ident = 
  match sv with
  | SpecVar (_, v, p) -> if (p==Primed) then (v^"\'") else v

let is_void_type t = match t with | Void -> true | _ -> false

let rec fv (f : formula) : spec_var list =
  let tmp = fv_helper f in
  let res = remove_dups_svl tmp in
  res

and fv_preserved_order (f : formula) : spec_var list =
  let tmp = fv_helper f in
  let res = Gen.BList.remove_dups_eq_reserved_order eq_spec_var tmp in
  res

and check_dups_svl ls = 
  let b=(Gen.BList.check_dups_eq eq_spec_var ls) in
  (if b then print_string ("!!!!ERROR==>duplicated vars:>>"^(!print_svl ls)^"!!")); b 

and fv_helper (f : formula) : spec_var list = match f with
  | BForm (b,_) -> bfv b
  | And (p1, p2,_) -> combine_pvars p1 p2 fv_helper
  | Or (p1, p2, _,_) -> combine_pvars p1 p2 fv_helper
  | Not (nf, _,_) -> fv_helper nf
  | Forall (qid, qf, _,_) -> remove_qvar qid qf
  | Exists (qid, qf, _,_) -> remove_qvar qid qf
  | AndList l -> fold_l_snd fv_helper l

and combine_pvars p1 p2 helper = (helper p1) @ (helper p2)

and all_vars_helper (f : formula) : spec_var list = match f with
  | BForm (b,_) -> bfv b
  | And (p1, p2,_) -> combine_pvars p1 p2 all_vars_helper
  | Or (p1, p2, _,_) -> combine_pvars p1 p2 all_vars_helper
  | Not (nf, _,_) -> all_vars_helper nf
  | Forall (qid, qf, _,_) 
  | Exists (qid, qf, _,_) -> qid::(all_vars_helper qf) 
  | AndList l -> fold_l_snd all_vars_helper l

and all_vars (f : formula) : spec_var list =
  let tmp = all_vars_helper f in
  let res = remove_dups_svl tmp in
  res
(*typ=None => choose all perm vars
  typ = Some ct => choose certain type
*)
(* and varperm_of_formula (f : formula) typ : spec_var list = *)
(*   let rec helper f typ =                                   *)
(*     (match f with                                          *)
(*       | BForm (b,_) -> varperm_of_b_formula b typ          *)
(*       | And (p1, p2,_) -> (helper p1 typ)@(helper p2 typ)  *)
(*       | AndList b-> fold_l_snd (fun c-> helper c typ) b    *)
(*       | Or (p1, p2, _,_) ->                                *)
(*             (*TO CHECK: may use approximation*)            *)
(*             let ls1 = helper p1 typ in                     *)
(*             let ls2 = helper p2 typ in                     *)
(*             ls1@ls2                                        *)
(*       | Not (nf, _,_) -> helper nf typ                     *)
(*       | Forall (qid, qf, _,_) -> helper qf typ             *)
(*       | Exists (qid, qf, _,_) -> helper qf typ)            *)
(*   in helper f typ                                          *)

(*typ=None => choose all perm vars
  typ = Some ct => choose certain type
*)
(* and varperm_of_b_formula (bf : b_formula) typ : spec_var list = *)
(*   let (pf,_) = bf in                                            *)
(*   (match pf with                                                *)
(*     | VarPerm (t,ls,_) ->                                       *)
(*           (match typ with                                       *)
(*             | None -> ls                                        *)
(*             | Some ct ->                                        *)
(*                   if (ct==t) then ls else [])                   *)
(*     | _ -> [])                                                  *)


and remove_qvar qid qf =
  let qfv = fv_helper qf in
  Gen.BList.difference_eq eq_spec_var qfv [qid]

and bfv (bf : b_formula) =
  let (pf,sl) = bf in
  match pf with
  | Frm (fv,_) -> [fv]
  | BConst _ -> []
  | XPure xp -> begin
      match xp.xpure_view_node with
      | None -> xp.xpure_view_arguments
      | Some r -> r::xp.xpure_view_arguments
    end
  | BVar (bv, _) -> [bv]
  | Lt (a1, a2, _) 
  | Lte (a1, a2, _) 
  | Gt (a1, a2, _) 
  | Gte (a1, a2, _) 
  | SubAnn (a1, a2, _) 
  | Eq (a1, a2, _) 
  | Neq (a1, a2, _) -> combine_avars a1 a2
  | EqMax (a1, a2, a3, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    let fv3 = afv a3 in
    remove_dups_svl (fv1 @ fv2 @ fv3)
  | EqMin (a1, a2, a3, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    let fv3 = afv a3 in
    remove_dups_svl (fv1 @ fv2 @ fv3)
  | BagIn (v, a1, _) ->
    let fv1 = afv a1 in
    [v] @ fv1
  | BagNotIn (v, a1, _) ->
    let fv1 = afv a1 in
    [v] @ fv1
  | BagSub (a1, a2, _) -> combine_avars a1 a2
  | BagMax (v1, v2, _) ->remove_dups_svl ([v1] @ [v2])
  | BagMin (v1, v2, _) ->remove_dups_svl ([v1] @ [v2])
  | ListIn (a1, a2, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    fv1 @ fv2
  | ListNotIn (a1, a2, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    fv1 @ fv2
  | ListAllN (a1, a2, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    fv1 @ fv2
  | ListPerm (a1, a2, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    fv1 @ fv2
  | RelForm (r, args, _) ->
    let vid = r in
    vid::remove_dups_svl (List.fold_left List.append [] (List.map afv args))
  | ImmRel (r, cond, _) -> 
    let fvr = bfv (r, sl) in
    fvr
  (* An Hoa *)
  (* | VarPerm (t,ls,_) -> ls *)
  | LexVar l_info ->
    List.concat (List.map afv (l_info.lex_exp @ l_info.lex_tmp))

and combine_avars (a1 : exp) (a2 : exp) : spec_var list =
  let fv1 = afv a1 in
  let fv2 = afv a2 in
  remove_dups_svl (fv1 @ fv2)

and afv (af : exp) : spec_var list =
  match af with
  | Null _ 
  | IConst _ 
  | AConst _ 
  | InfConst _
  | NegInfConst _
  | Tsconst _
  | FConst _ -> []
  | Tup2 ((a1,a2),_) -> combine_avars a1 a2
  | Bptriple ((ec,et,ea),_) -> [ec;et;ea]
  | Var (sv, _) -> if (is_hole_spec_var sv) then [] else [sv]
  | Level (sv, _) -> if (is_hole_spec_var sv) then [] else [sv]
  | Add (a1, a2, _) -> combine_avars a1 a2
  | Subtract (a1, a2, _) -> combine_avars a1 a2
  | Mult (a1, a2, _) | Div (a1, a2, _) -> combine_avars a1 a2
  | Max (a1, a2, _) -> combine_avars a1 a2
  | Min (a1, a2, _) -> combine_avars a1 a2
  | TypeCast (_, a, _) -> afv a
  | Bag (alist, _) -> let svlist = afv_list alist in
    remove_dups_svl svlist
  | BagUnion (alist, _) -> let svlist = afv_list alist in
    remove_dups_svl svlist
  | BagIntersect (alist, _) -> let svlist = afv_list alist in
    remove_dups_svl svlist
  | BagDiff(a1, a2, _) -> combine_avars a1 a2
  | List (alist, _) -> let svlist = afv_list alist in
    remove_dups_svl svlist
  | ListAppend (alist, _) -> let svlist = afv_list alist in
    remove_dups_svl svlist
  | ListCons (a1, a2, _) ->
    let fv1 = afv a1 in
    let fv2 = afv a2 in
    remove_dups_svl (fv1 @ fv2)  
  | ListHead (a, _)
  | ListTail (a, _)
  | ListLength (a, _)
  | ListReverse (a, _) -> afv a
  | Func (a, i, _) -> 
    let ifv = List.concat (List.map afv i) in
    remove_dups_svl (a :: ifv) 
  | ArrayAt (a, i, _) -> 
    let ifv = List.map afv i in
    let ifv = List.flatten ifv in
    begin
      match i with
      | [index] ->
        remove_dups_svl (a :: ifv)
      | _ ->
        remove_dups_svl (a :: ifv)
        (*failwith ("afv:"^(!print_exp af)^" Invalid index")*)
    end
  (* remove_dups_svl (a :: ifv) (\* An Hoa *\) *)
  | Template t ->
    t.templ_id::
    (List.concat (List.map afv t.templ_args)) 
(* @ (List.concat (List.map afv t.templ_unks)) *)

and afv_list (alist : exp list) : spec_var list = match alist with
  |[] -> []
  |a :: rest -> afv a @ afv_list rest

and is_max_min e =
  match e with
  | Max _ | Min _ -> true
  | _ -> false

and string_of_relation (e:relation) : string =
  match e with
  | ConstRel b -> if b then "True" else "False"
  | BaseRel (el,f) -> pr_pair (pr_list !print_exp) !print_formula (el,f)
  | UnionRel (r1,r2) -> (string_of_relation r1)^"\n"^(string_of_relation r2)^"\n"

and isConstTrue_debug (p:formula) =
  Debug.no_1 "isConsTrue" !print_formula string_of_bool isConstTrue p

and isTrivTerm (p:formula) = match p with
  | BForm ((LexVar l, _),_) -> 
    ((is_Term l.lex_ann) || (is_MayLoop l.lex_ann)) && l.lex_exp == []
  | _ -> false

and is_Gt_formula (f: formula) = 
  match f with
  | BForm ((Gt _, _), _) -> true
  | _ -> false

and is_strict_formula (f: formula) =
  match f with
  | BForm ((Gt _, _), _)
  | BForm ((Lt _, _), _) -> true
  | _ -> false

and isConstBTrue (p:b_formula) =
  let (pf,_) = p in
  match pf with
  | BConst (true, pos) -> true
  | _ -> false

and isConstBFalse (p:b_formula) =
  let (pf,_) = p in
  match pf with
  | BConst (false, pos) -> true
  | _ -> false

and isBVar (f: formula) = 
  match f with
  | BForm ((BVar (_, _), _), _) -> true
  | Not (f, _, _) -> isBVar f
  | _ -> false

and getBVar (f: formula) =
  match f with
  | BForm ((BVar (bv, _), _), _) -> Some (bv, true)
  | Not (f, _, _) -> 
    let bv = getBVar f in
    begin match bv with
      | None -> None
      | Some (bv, v) -> Some (bv, not v) end
  | _ -> None

and isSubAnn (p:formula) =
  match p with
  | BForm ((Lte (Var (_,_), IConst(_,_), _),_),_) -> true
  | _ -> false

and getAnn (p:formula) =
  match p with
  | BForm ((Lte (Var (_,_), IConst(i,_), _),_),_) -> [i]
  | _ -> []

and getMaxAnn (p:formula) =
  match p with
  | BForm ((Lte (Var (_,_), IConst(i,_), _),_),_) -> [i]
  | BForm ((Gte (IConst(i,_), Var (_,_), _),_),_) -> [i]
  | _ -> []

and getMinAnn (p:formula) =
  match p with
  | BForm ((Gte (Var (_,_), IConst(i,_), _),_),_) -> [i]
  | BForm ((Lte (IConst(i,_), Var (_,_),_), _),_) -> [i]
  | _ -> []

and getEqAnn (p:formula) =
  match p with
  | BForm ((Eq (IConst(i,_), Var (_,_),_), _),_) -> [i]
  | BForm ((Eq (Var (_,_),IConst(i,_),_), _),_) -> [i]
  | _ -> []

and is_null (e : exp) : bool =
  match e with
  | Null _ -> true
  | _ -> false

and is_zero_int (e : exp) : bool = match e with  | IConst (0, _) -> true
                                                 | _ -> false

and is_zero_float (e : exp) : bool = match e with
  | FConst (0.0, _) -> true
  | _ -> false

and is_zero (e: exp): bool = 
  match e with
  | IConst (0, _) -> true
  | FConst (0.0, _) -> true
  | _ -> false

and is_var (e : exp) : bool =
  match e with
  | Var _ -> true
  | _ -> false

and is_num (e : exp) : bool =
  match e with
  | IConst _ -> true
  | FConst _ -> true
  | _ -> false

and to_int_const e t =
  match e with
  | IConst (i, _) -> i
  | FConst (f, _) ->
    begin
      match t with
      | Ceil -> int_of_float (ceil f)
      | Floor -> int_of_float (floor f)
    end
  | _ -> 0

and is_int (e : exp) : bool =
  match e with
  | IConst _ -> true
  | _ -> false

and is_nat (e: exp): bool =
  match e with
  | IConst (i, _) -> i >= 0
  | _ -> false

and is_float (e : exp) : bool =
  match e with
  | FConst _ -> true
  | _ -> false

and is_specific_val (e: exp): bool =
  is_int e || is_float e || is_null e

and eq_num_exp e1 e2 =
  match e1, e2 with
  | IConst (i1, _), IConst (i2, _) -> i1 == i2
  | _ -> false

and include_specific_val (f: formula): bool = match f with
  | BForm (bf,_) -> include_specific_val_bf bf
  | And (f1,f2,_) -> include_specific_val f1 || include_specific_val f2
  | Or (f1,f2,_,_) -> include_specific_val f1 || include_specific_val f2
  | Not (f,_,_) -> include_specific_val f
  | Forall (_,f,_,_) -> include_specific_val f
  | Exists (_,f,_,_) -> include_specific_val f
  | AndList l -> exists_l_snd include_specific_val l

and include_specific_val_bf (bf: b_formula): bool =
  let (pf,_) = bf in
  match pf with
  | Lt (e1,e2,_)
  | Lte (e1,e2,_)
  | Gt (e1,e2,_)
  | Gte (e1,e2,_)
  | Eq (e1,e2,_)
  | Neq (e1,e2,_) -> is_specific_val e1 || is_specific_val e2
  | _ -> false

and get_num_int (e : exp) : int =
  match e with
  | IConst (b,_) -> b
  | _ -> 0

and get_num_int_opt (e : exp) =
  match e with
  | IConst (b,_) -> Some b
  | _ -> None

and get_num_float (e : exp) : float =
  match e with
  | FConst (f, _) -> f
  | _ -> 0.0

and get_num_int_list_bf (bf: b_formula) : int list =
  let (pf,_) = bf in
  match pf with
  | Lt (e1,e2,_)
  | Lte (e1,e2,_)
  | Gt (e1,e2,_)
  | Gte (e1,e2,_)
  | Eq (e1,e2,_)
  | Neq (e1,e2,_) ->
    let l1 = if is_int e1 then [get_num_int e1] else [] in
    let l2 = if is_int e2 then [get_num_int e2] else [] in
    l1@l2
  | _ -> []

and get_num_int_list (f : formula) : int list = match f with
  | BForm (bf,_) -> get_num_int_list_bf bf
  | And (f1,f2,_) -> (get_num_int_list f1) @ (get_num_int_list f2)
  | Or (f1,f2,_,_) -> (get_num_int_list f1) @ (get_num_int_list f2)
  | Not (f,_,_) -> get_num_int_list f
  | Forall (_,f,_,_) -> get_num_int_list f
  | Exists (_,f,_,_) -> get_num_int_list f
  | AndList l -> List.fold_left (fun acc (_,f) -> acc@(get_num_int_list f)) [] l

and is_var_num (e : exp) : bool =
  match e with
  | Var _ -> true
  | IConst _ -> true
  | FConst _ -> true
  | _ -> false

and is_var_ann (e : exp) : bool =
  match e with
  | Var _ -> true
  | AConst _ -> true
  | _ -> false

and to_var (e : exp) : spec_var =
  match e with
  | Var (sv, _) -> sv
  | _ -> failwith ("to_var: argument is not a variable")

and can_be_aliased_aux_x with_null (e : exp) : bool =
  match e with
  | Var _ -> true
  (* null is necessary in this case: p=null & q=null.
     If null is not considered, p=q is not inferred. *)
  | Null _ -> with_null
  | _ -> false


and can_be_aliased_aux with_null (e : exp) : bool =
  let pr1 = string_of_bool in
  let pr2 = !print_exp in
  Debug.no_2 "can_be_aliased_aux" pr1 pr2 pr1 can_be_aliased_aux_x with_null e

and can_be_aliased (e : exp) : bool =
  can_be_aliased_aux true e
(* null is necessary in this case: p=null & q=null.
   If null is not considered, p=q is not inferred. *)

and b_f_ptr_equations_aux with_null f =
  let (pf, _) = f in
  match pf with
  | Eq (e1, e2, _) ->
    let b = can_be_aliased_aux with_null e1 && can_be_aliased_aux with_null e2 in
    if not b then [] else [(get_alias e1, get_alias e2)]
  | _ -> [] 

and b_f_ptr_equations f = b_f_ptr_equations_aux true f

and is_bf_ptr_equations bf =
  let (pf,_) = bf in
  match pf with
  | Eq (e1, e2, _) -> can_be_aliased_aux true e1 && can_be_aliased_aux true e2
  | _ -> false

and is_pure_ptr_equations f = match f with
  | BForm (bf,_) -> is_bf_ptr_equations bf
  | _ -> false

and remove_ptr_equations f is_or = match f with
  | BForm (bf,_) -> 
    if is_bf_ptr_equations bf then 
      if is_or then mkFalse no_pos
      else mkTrue no_pos 
    else f
  | And (f1,f2,p) -> mkAnd (remove_ptr_equations f1 false) (remove_ptr_equations f2 false) p
  | AndList b -> mkAndList (map_l_snd (fun c-> remove_ptr_equations c false) b)
  | Or (f1,f2,o,p) -> mkOr (remove_ptr_equations f1 true) (remove_ptr_equations f2 true) o p
  | Not (f,o,p) -> Not (remove_ptr_equations f false,o,p)
  | Forall (v,f,o,p) -> Forall (v,remove_ptr_equations f false,o,p)
  | Exists (v,f,o,p) -> Exists (v,remove_ptr_equations f false,o,p)

and pure_ptr_equations (f:formula) : (spec_var * spec_var) list = 
  x_add pure_ptr_equations_aux true f

and pure_ptr_equations_aux_x with_null (f:formula) : (spec_var * spec_var) list = 
  let rec prep_f f = match f with
    | And (f1, f2, pos) -> (prep_f f1) @ (prep_f f2)
    | AndList b -> fold_l_snd prep_f b
    | BForm (bf,_) -> b_f_ptr_equations_aux with_null bf
    | _ -> [] in 
  prep_f f

and pure_ptr_equations_aux with_null (f:formula) : (spec_var * spec_var) list = 
  let pr1 = string_of_bool in
  let pr2 = !print_formula in
  let pr3 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_2 "pure_ptr_equations_aux" pr1 pr2 pr3 pure_ptr_equations_aux_x with_null f 

and get_int_equality_aux f = []

and get_int_equality (f:formula) : (spec_var * spec_var) list = 
  (* let pr1 = string_of_bool in *)
  let pr2 = !print_formula in
  let pr3 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_1 "get_int_equality" pr2 pr3 get_int_equality_aux f 


and get_alias (e : exp) : spec_var =
  match e with
  | Var (sv, _) -> sv
  | Null _ -> null_var (* it is safe to name it "null" as no other variable can be named "null" *)
  | _ -> failwith ("get_alias: argument is neither a variable nor null")

(*and can_be_aliased_aux_bag with_emp (e : exp) : bool =*)
(*  match e with*)
(*    | Var _ -> true*)
(*    | Bag ([],_) -> with_emp*)
(*    | BagUnion ([Var (_,_); Bag ([Var(_,_)],_)], _) *)
(*    | BagUnion ([Var (_,_); Bag ([Var(_,_)],_)], _) -> true*)
(*    | _ -> false*)

(*and get_alias_bag (e : exp) : spec_var =*)
(*  match e with*)
(*    | Var (sv, _) -> sv*)
(*    | Bag ([],_) -> SpecVar (Named "", "emptybag", Unprimed)*)
(*    | BagUnion ([Var (sv1,_); Bag ([Var(sv2,_)],_)], _) -> *)
(*      SpecVar (Named "", "unionbag" ^ (name_of_spec_var sv1) ^ (name_of_spec_var sv2), Unprimed)*)
(*    | BagUnion ([Var (sv1,_); Bag ([Var(sv2,_)],_)], _) -> *)
(*      SpecVar (Named "", "unionbag" ^ (name_of_spec_var sv2) ^ (name_of_spec_var sv1), Unprimed)*)
(*    | _ -> report_error no_pos "Not a bag or a variable or null"*)

and can_be_aliased_aux_bag with_emp (e : exp) : bool =
  match e with
  | Var _ -> true
  | Subtract (_,Subtract (_,Var _,_),_) -> true
  | Bag ([],_) -> with_emp
  | Bag (es,_) -> List.for_all (can_be_aliased_aux_bag with_emp) es
  | BagUnion (es, _) -> List.for_all (can_be_aliased_aux_bag with_emp) es
  | _ -> false

and get_alias_bag (e : exp) : spec_var =
  match e with
  | Var (sv, _)
  | Subtract (_,Subtract (_,Var (sv,_),_),_) -> sv
  | Bag ([],_) -> SpecVar (Globals.null_type (* Named "" *), "emptybag", Unprimed)
  | Bag (es,_) -> 
    SpecVar (Globals.null_type, "bag" ^ (List.fold_left (fun x y -> x ^ name_of_exp y) "" es), Unprimed)
  | BagUnion (es, _) -> 
    SpecVar (Globals.null_type, "unionbag" ^ (List.fold_left (fun x y -> x ^ name_of_exp y) "" es), Unprimed)
  | _ -> report_error no_pos "Not a bag or a variable or a bag_union or null"

and name_of_exp (e: exp): string =
  match e with
  | Var (sv, _)
  | Subtract (_,Subtract (_,Var (sv,_),_),_) -> name_of_spec_var sv
  | Bag ([],_) -> "emptybag"
  | Bag (es,_)
  | BagUnion (es, _) -> (List.fold_left (fun x y -> x ^ name_of_exp y) "" es)
  | _ -> ""

and is_object_var (sv : spec_var) = match sv with
  | SpecVar (Named _, _, _) -> true
  | _ -> false

and exp_is_object_var (e : exp) =
  match e with
  | Var(SpecVar (Named _, _, _),_) -> true
  | _ -> false

and exp_is_boolean_var (e : exp) =
  match e with
  | Var (v,_) -> is_bool_typ v
  | _ -> false

and get_boolean_var (e : exp) =
  match e with
  | Var (SpecVar (Bool, _, _) as v,_) -> Some v
  | _ -> None

and is_bag (e : exp) : bool =
  match e with
  | Bag _
  | BagUnion _
  | BagIntersect _
  | BagDiff _ -> true
  | Var (sv,_) ->
    if (is_bag_typ sv) then true else false
  | _ -> false

(* ignore bag vars *)
and is_bag_weak (e : exp) : bool =
  match e with
  | Bag _
  | BagUnion _
  | BagIntersect _
  | BagDiff _ -> true
  | _ -> false

and is_list (e : exp) : bool =
  match e with
  | List _
  | ListCons _
  | ListTail _
  | ListAppend _
  | ListReverse _ -> true
  | _ -> false


and is_bag_bform (b: b_formula) : bool =
  let (pf,_) = b in
  match pf with
  | BagIn _ | BagNotIn _ | BagSub _ | BagMin _ | BagMax _ -> true
  | _ -> false

and is_list_bform (b: b_formula) : bool =
  let (pf,_) = b in
  match pf with
  | ListIn _ | ListNotIn _ | ListAllN _ | ListPerm _ -> true
  | _ -> false

and is_bool_bform b = 
  let (pf, _) = b in
  match pf with
  | BVar _ -> true
  | _ -> false

and is_bool_formula f = 
  match f with
  | BForm (bf, _) -> is_bool_bform bf
  | Not (f, _, _) -> is_bool_formula f
  | _ -> false

and is_arith (e : exp) : bool =
  match e with
  | Add _
  | Subtract _
  | Mult _
  | Div _
  | Min _
  | Max _
  | ListHead _
  | ListLength _ -> true
  | _ -> false

and is_bag_type (t : typ) = match t with
  | (Globals.BagT _) -> true
  | _ -> false

and is_list_type (t : typ) = match t with
  | Globals.List _  -> true
  | _ -> false

and is_int_type (t : typ) = match t with
  | Int -> true
  | _ -> false

and is_int_convertible_type (t : typ) = match t with
  | Int | Bool | TVar _ | Named _ -> true
  | _ -> false

and is_num_type (t : typ) = match t with
  | NUM -> true
  | _ -> false

and is_ann_type (t : typ) = match t with
  | AnnT -> true
  | _ -> false

and is_float_type (t : typ) = match t with
  | Float -> true
  | _ -> false

and is_float_var (sv : spec_var) : bool = is_float_type (type_of_spec_var sv)

and is_int_var (sv : spec_var) : bool = is_int_type (type_of_spec_var sv)

(* WN : int/bool/ptr type that can be converted to int *)
and is_int_convertible_var (sv : spec_var) : bool = is_int_convertible_type (type_of_spec_var sv)

and is_list_var (sv : spec_var) : bool = is_list_type (type_of_spec_var sv)

and is_float_exp exp = 
  let rec helper exp = 
    match exp with
    | Var (v,_) -> is_float_var v (* check type *)
    | FConst v -> true
    | Add (e1, e2, _) | Subtract (e1, e2, _) | Mult (e1, e2, _) -> (helper e1) || (helper e2)
    | Div (e1, e2, _) -> true
    (* Omega don't accept / operator, we have to manually transform the formula *)
            (*
              (match e2 with
              | IConst _ -> is_linear_exp e1
              | _ -> false)
            *)
    | _ -> false
  in
  helper exp

and is_float_bformula b = 
  let b, _ = b in
  match b with
  | Lt (e1, e2, _) | Lte (e1, e2, _) 
  | Gt (e1, e2, _) | Gte (e1, e2, _)
  | Eq (e1, e2, _) | Neq (e1, e2, _)
    -> (is_float_exp e1) || (is_float_exp e2)
  | EqMax (e1, e2, e3, _) | EqMin (e1, e2, e3, _)
    -> (is_float_exp e1) || (is_float_exp e2) || (is_float_exp e3)
  | _ -> false

and is_float_formula_x f0 = 
  let rec helper f0=  match f0 with
    | BForm (b,_) -> is_float_bformula b
    | Not (f, _,_) | Forall (_, f, _,_) | Exists (_, f, _,_) ->
      is_float_formula f;
    | And (f1, f2, _) | Or (f1, f2, _,_) ->
      (helper f1) || (helper f2)
    | AndList l -> exists_l_snd helper l
  in helper f0

and is_float_formula f0 =
  Debug.no_1 "is_float_formula" 
    !print_formula string_of_bool
    is_float_formula_x f0

and is_object_type (t : typ) = match t with
  | Named _ -> true
  | _ -> false

(* WN : is this simplify to help other provers? *)
and should_simplify (f : formula) =
  if !Globals.simplify_imply 
  then
    match f with
    | Or (f1,f2,_,_)-> should_simplify f1 || should_simplify f2
    | AndList b -> exists_l_snd should_simplify b
    | Exists _ -> true
    | _ -> false
  else false
(* | Exists (_, Exists (_, (Exists _),_,_), _,_) -> true *)

and is_ineq_linking_bform (b : b_formula) : bool =
  let (pf, il) = b in
  match pf with
  | Neq _ ->
    (match il with
     | Some (true, _, _) -> true
     | _ -> false)
  | _ -> false

and is_eq_linking_bform (b : b_formula) : bool =
  let (pf, il) = b in
  match pf with
  | Eq _ ->
    (match il with
     | Some (true, _, _) -> true
     | _ -> false)
  | _ -> false

(* and is_varperm (f : formula) : bool= *)
(*   (match f with                      *)
(*     | BForm (b,_) -> is_varperm_b b  *)
(*     | _ -> false                     *)
(*   )                                  *)

(* and is_varperm_of_typ (f : formula) typ : bool= *)
(*   (match f with                                 *)
(*     | BForm (b,_) -> is_varperm_of_typ_b b typ  *)
(*     | _ -> false                                *)
(*   )                                             *)

(* and get_varperm_pure (f : formula) typ : spec_var list=                         *)
(*   (match f with                                                                 *)
(*     | BForm (b,_) -> get_varperm_b b typ                                        *)
(*     | AndList ls ->                                                             *)
(*         List.concat (List.map (fun (_,fi) -> get_varperm_pure fi typ) ls)       *)
(*     | And (f1,f2,_) ->                                                          *)
(*           let res1 = get_varperm_pure f1 typ in                                 *)
(*           let res2 = get_varperm_pure f2 typ in                                 *)
(*           (match typ with                                                       *)
(*             | VP_Zero -> (res1@res2) (*TO CHECK: merge or AND ???*)             *)
(*             | VP_Full -> (res1@res2)                                            *)
(*             | VP_Value -> (res1@res2)                                           *)
(*             | VP_Lend -> (res1@res2)                                            *)
(*             | VP_Frac _ -> (res1@res2)                                         *)
(*           )                                                                     *)
(*     | Or (f1,f2,_,_) ->                                                         *)
(*           let res1 = get_varperm_pure f1 typ in                                 *)
(*           let res2 = get_varperm_pure f2 typ in                                 *)
(*           (*approximation*)                                                     *)
(*           (match typ with                                                       *)
(*             | VP_Zero -> remove_dups_svl_ident (res1@res2) *)
(*             | VP_Full -> Gen.BList.intersect_eq eq_spec_var_ident res1 res2     *)
(*             | VP_Value -> Gen.BList.intersect_eq eq_spec_var_ident res1 res2    *)
(*             | VP_Lend -> remove_dups_svl_ident (res1@res2) *)
(*             | VP_Frac _ -> Gen.BList.intersect_eq eq_spec_var_ident res1 res2  *)
(*           )                                                                     *)
(*     | _ -> []                                                                   *)
(*   )                                                                             *)

(* and get_varperm_b (b : b_formula) typ: spec_var list =                          *)
(*   let (pf, il) = b in                                                           *)
(*   match pf with                                                                 *)
(*     | VarPerm (ct,ls,_) ->                                                      *)
(*           if (ct==typ) then ls                                                  *)
(*           else []                                                               *)
(*     | _ -> []                                                                   *)

(* and is_varperm_b (b : b_formula) : bool =                                       *)
(*   let (pf, il) = b in                                                           *)
(*   match pf with                                                                 *)
(*     | VarPerm _ -> true                                                         *)
(*     | _ -> false                                                                *)

(* and is_varperm_of_typ_b (b : b_formula) typ: bool =                             *)
(*   let (pf, il) = b in                                                           *)
(*   match pf with                                                                 *)
(*     | VarPerm (ct,_,_) ->                                                       *)
(*           if (ct==typ) then true                                                *)
(*           else false                                                            *)
(*     | _ -> false                                                                *)

and trans_eq_bform_x (b : b_formula) : b_formula =
  let (pf, il) = b in
  match pf with
  | Neq _ -> 
    (* (pf, Some (true, Globals.fresh_int(), [])) *)
    if (List.length (bfv b)) > 1
    then (pf, Some (true, Globals.fresh_int(), []))
    else (pf, None)
  | Eq _ -> (pf, None)
  | _ -> b

and trans_eq_bform (b : b_formula) : b_formula =
  let pr = !print_b_formula in
  Debug.no_1 "trans_eq_bform" pr pr trans_eq_bform_x b

and trans_const_bforms_x (bl: b_formula list) : b_formula list =
  let eq_constrs, others = List.partition (fun (pf, _) ->
      match pf with | Eq _ -> true | _ -> false) bl in
  let const_vars, eq_consts, eq_others = partition_by_const eq_constrs in
  (* mark_linking_const_var in eq_others @ others *)
  let marked_others = List.map (fun ((pf, il) as b) ->
      let lnk_vars, _ = List.partition (fun v -> 
          Gen.BList.mem_eq eq_spec_var v const_vars) (bfv b) in
      let lnk_var_exps = List.map (fun v -> mkVar v no_pos) lnk_vars in	 
      let n_il = match il with
        | None -> Some (false, Globals.fresh_int (), lnk_var_exps)
        | Some (is_lnk, _, e_lnk) -> Some (is_lnk, Globals.fresh_int (), e_lnk @ lnk_var_exps)
      in (pf, n_il)) (others @ eq_others)
  in eq_consts @ marked_others

and trans_const_bforms (bl: b_formula list) : b_formula list =
  let pr_bl = pr_list !print_b_formula in
  let pr_out = pr_bl in
  Debug.no_1 "trans_const_bforms" pr_bl pr_out trans_const_bforms_x bl

and partition_by_const eql =
  let rec helper (lbl, eq_const_lst) eq_lst = 
    let n_lbl, eq_consts, eq_others = 
      List.fold_left (fun (a_lbl, a_eq_consts, a_others) e ->
          let lnk_vars, const_vars = 
            List.partition (fun v -> Gen.BList.mem_eq eq_spec_var v a_lbl) (bfv e) in
          (* const_vars = Gen.BList.difference_eq eq_spec_var (bfv e) a_lbl *)
          (* Condition for a new linking constant variables *)
          if (List.length const_vars) == 1 then
            let lnk_var_exps = List.map (fun v -> mkVar v no_pos) lnk_vars in
            let (pf, il) = e in
            let n_il = match il with
              | None -> Some (false, Globals.fresh_int (), lnk_var_exps)
              | Some (is_lnk, _, e_lnk) -> Some (is_lnk, Globals.fresh_int (), e_lnk @ lnk_var_exps)
            in
            let n_e = (pf, n_il) in
            (a_lbl @ const_vars), (a_eq_consts @ [n_e]), a_others
          else a_lbl, a_eq_consts, (a_others @ [e])
        ) (lbl, [], []) eq_lst in
    if eq_consts == [] then (lbl, eq_const_lst, eq_lst)
    else helper (n_lbl, eq_const_lst @ eq_consts) eq_others
  in helper ([], []) eql

and is_b_form_arith (b: b_formula) :bool = let (pf,_) = b in
  match pf with
  | Frm _ | BConst _  | BVar _ | SubAnn _ | LexVar _ | XPure _ -> true
  | Lt (e1,e2,_) | Lte (e1,e2,_)  | Gt (e1,e2,_) | Gte (e1,e2,_) | Eq (e1,e2,_) 
  | Neq (e1,e2,_) -> (is_exp_arith e1)&&(is_exp_arith e2)
  | EqMax (e1,e2,e3,_) | EqMin (e1,e2,e3,_) -> (is_exp_arith e1)&&(is_exp_arith e2) && (is_exp_arith e3)
  (* bag formulas *)
  | BagIn _ | BagNotIn _ | BagSub _ | BagMin _ | BagMax _
  (* | VarPerm _ *)
  (* list formulas *)
  | ListIn _ | ListNotIn _ | ListAllN _ | ListPerm _
  | RelForm _ | ImmRel _ -> false (* An Hoa *)

and is_xpure p=
  match p with
  | BForm (b,_) ->  is_b_form_xpure b
  | _ -> false

and is_b_form_xpure (b: b_formula) :bool = let (pf,_) = b in
  match pf with
  | XPure _ -> true
  | _ -> false

(* Expression *)
and is_exp_arith (e:exp) : bool=
  match e with
  | Var (sv,pos) ->        (*waitlevel is a kind of bag constraints*)
    if (name_of_spec_var sv = Globals.waitlevel_name) then false else true
  | Null _  | IConst _ | AConst _ | InfConst _ | NegInfConst _ | FConst _ 
  | Level _ -> true
  | Add (e1,e2,_)  | Subtract (e1,e2,_)  | Mult (e1,e2,_)
  | Div (e1,e2,_)  | Max (e1,e2,_)  | Min (e1,e2,_) -> (is_exp_arith e1) && (is_exp_arith e2)
  | TypeCast(_, e1, _) -> is_exp_arith e1
  (* bag expressions *)
  | Bag _ | BagUnion _ | BagIntersect _ | BagDiff _
  (* list expressions *)
  | List _ | ListCons _ | ListHead _ | ListTail _
  | ListLength _ | ListAppend _ | ListReverse _ -> false
  | Tsconst _ -> false
  | Tup2  _ -> false
  | Bptriple _ -> false
  | Func _ -> true
  | ArrayAt _ -> true (* An Hoa : a[i] is just a value *)
  | Template _ -> true

and is_formula_arith_x (f:formula) :bool = match f with
  | BForm (b,_) -> is_b_form_arith b
  | And (f1,f2,_) | Or (f1,f2,_,_)-> (is_formula_arith f1)&&(is_formula_arith f2)
  | Not (f,_,_) | Forall (_,f,_,_) | Exists (_,f,_,_)-> (is_formula_arith f)
  | AndList l -> all_l_snd  is_formula_arith l

and is_formula_arith (f:formula) :bool =
  Debug.no_1 "is_formula_arith" !print_formula string_of_bool
    is_formula_arith_x f

and is_exp_ann (e:exp) : bool =
  match e with
  | Var (sv, _) -> is_ann_typ sv
  | AConst (_, _) -> true
  | _ -> false
(* smart constructor *)

(*Create a locklevel of a lock sv*)
and mkLevel sv pos = Level (sv, pos)

and mkLevelVar p = (SpecVar (level_data_typ, level_name, p))

and mkWaitlevelVar p = (SpecVar (waitlevel_typ, waitlevel_name, p))
(*********BAG CONSTRAINT***************)
(*create lockset var, primed or unprimed*)
and mkLsVar p = (SpecVar (ls_typ, ls_name, p))

and mkLsmuVar p = (SpecVar (lsmu_typ, lsmu_name, p))

and mkBag svl pos = Bag (svl,pos)

and mkEmptyBag pos = mkBag [] pos

(*exps: expression list*)
and mkBagUnion exps pos = BagUnion (exps,pos) 

(* E1\E2*)
and mkBagDiff e1 e2 pos = BagDiff (e1,e2,pos) 

(*v notin S*)
and mkBagNotIn v exp pos = BagNotIn (v,exp,pos) 

and mkBagNotInExp v exp pos =
  let bf = mkBagNotIn v exp pos in
  BForm ((bf, None),None)

(* v in S*)
and mkBagIn v exp pos = BagIn (v,exp,pos)

and mkBagInExp v exp pos =
  let bf = mkBagIn v exp pos in
  BForm ((bf, None),None)

(* e1 is subset of e2 *)
and mkBagSub e1 e2 pos = BagSub (e1,e2,pos)

and mkBagSubExp e1 e2 pos =
  let bf = mkBagSub e1 e2 pos in
  BForm ((bf, None),None)

(******************************************)

and mkRes t = SpecVar (t, res_name, Unprimed)

and mkeRes t = SpecVar (t, eres_name, Unprimed)

and mkRel_sv n = SpecVar (RelT[], n, Unprimed)

and mkXPure_sv v = SpecVar (RelT[], v, Unprimed)

and mkAdd a1 a2 pos = Add (a1, a2, pos)

and mkSubtract a1 a2 pos = Subtract (a1, a2, pos)

and mkIConst a pos = IConst (a, pos)

and mkInfConst pos = InfConst (zinf_str, pos)

and mkNegInfConst pos = mkSubtract (mkIConst 0 pos) (mkInfConst pos) pos

and mkFConst a pos = FConst (a, pos)

and mkMult a1 a2 pos = Mult (a1, a2, pos)

and mkDiv a1 a2 pos = Div (a1, a2, pos)

and mkMax a1 a2 pos = Max (a1, a2, pos)

and mkMin a1 a2 pos = Min (a1, a2, pos)

and mkEqMax a1 a2 a3 pos = EqMax (a1, a2, a3,pos)

and mkEqMin a1 a2 a3 pos = EqMin (a1, a2, a3,pos)

and mkVar sv pos = Var (sv, pos)

(* dedicated name for imm sv ecoding the constant ann a *)
and name_for_imm_sv a = imm_const_prefix ^ (string_of_heap_ann a)

(* special spec var denoting ann constant *)
and mkAnnSVar a =  SpecVar (AnnT, name_for_imm_sv a, Unprimed)

and exp_of_template t = match t.templ_body with
  | None ->
    let pos = t.templ_pos in
    List.fold_left (fun a (c, e) -> mkAdd a (mkMult c e pos) pos) 
      (List.hd t.templ_unks) (List.combine (List.tl t.templ_unks) t.templ_args)
  | Some b -> b

and template_of_exp e = match e with
  | Template t -> t
  | _ -> report_error no_pos "[cpure.ml][template_of_exp]: The expression is not a template."

and exp_of_template_exp e = match e with
  | Template t -> exp_of_template t
  | _ -> e

and mkTemplate id (args: exp list) pos =
  let mkUnk i pos = mkVar (SpecVar (Int, id ^ "_" ^ (string_of_int i), Unprimed)) pos in
  let t_unks = List.fold_left (fun (a, i) _ -> a @ [mkUnk i pos], i+1) ([], 1) args in 
  let t_unks = (mkUnk 0 pos)::(fst t_unks) in
  let t_typ = mkFuncT (List.map (fun e -> if is_float_exp e then Float else Int) args) Int in
  let t = {
    templ_id = SpecVar(t_typ, id, Unprimed);
    templ_args = args;
    templ_unks = t_unks;
    templ_body = None;
    templ_pos = pos; } in 
  { t with templ_body = Some (exp_of_template t); }

and mkTemplate_sv sv (args: exp list) pos = 
  let id = name_of_spec_var sv in
  let mkUnk i pos = mkVar (SpecVar (Int, id ^ "_" ^ (string_of_int i), Unprimed)) pos in
  let t_unks = List.fold_left (fun (a, i) _ -> a @ [mkUnk i pos], i+1) ([], 1) args in 
  let t_unks = (mkUnk 0 pos)::(fst t_unks) in
  let t = {
    templ_id = sv;
    templ_args = args;
    templ_unks = t_unks;
    templ_body = None;
    templ_pos = pos; } in 
  { t with templ_body = Some (exp_of_template t); }

and mkTemplateExp id (args: exp list) pos =
  Template (mkTemplate id args pos)

and mkBVar v p pos = BVar (SpecVar (Bool, v, p), pos)

and mkLexVar t_ann m i pos = 
  LexVar {
    lex_ann = t_ann;
    lex_exp = m;
    lex_fid = "";
    lex_tmp = i;
    lex_loc = pos; }

and mkPure bf = BForm ((bf,None), None)

and mkLexVar_pure a l1 l2 = 
  let bf = mkLexVar a l1 l2 no_pos in
  let p = mkPure bf in
  p

and mkBVar_pure v p pos = mkPure (mkBVar v p pos)

and mkVarNull v pos = 
  if is_null_const v then Null pos
  else mkVar v pos

and mkPtrEqn v1 v2 pos = 
  let v1 = mkVarNull v1 pos in
  let v2 = mkVarNull v2 pos in
  mkEqExp v1 v2 pos

and mkEqn v1 v2 pos = 
  let v1 = mkVar v1 pos in
  let v2 = mkVar v2 pos in
  mkEqExp v1 v2 pos

and mkPtrNeqEqn v1 v2 pos =
  let v1 = mkVarNull v1 pos in
  let v2 = mkVarNull v2 pos in
  mkNeqExp v1 v2 pos

and mklsPtrNeqEqn vs pos =
  let rec helper vs=
    match vs with
    | [] -> []
    | [v] -> []
    | v::tl ->
      (List.map (fun b -> mkPtrNeqEqn v b pos) tl) @ (helper tl)
  in
  if List.length vs > 1 then
    let disj_sets= helper vs in
    Some (List.fold_left
            (fun a b -> mkAnd a b pos) (mkTrue no_pos) disj_sets)
  else None

and mkLt a1 a2 pos =
  if is_max_min a1 || is_max_min a2 then
    failwith ("max/min can only be used in equality")
  else
    Lt (a1, a2, pos)

and mkLte a1 a2 pos =
  if is_max_min a1 || is_max_min a2 then
    failwith ("max/min can only be used in equality")
  else
    Lte (a1, a2, pos)

and mkGt a1 a2 pos =
  if is_max_min a1 || is_max_min a2 then
    failwith ("max/min can only be used in equality")
  else
    Gt (a1, a2, pos)

and mkFormulaFromXP xp=
  BForm ((XPure xp,None),None)

and mkRel rel args pos=
  BForm ((RelForm (rel,args,pos), None) , None)

and mkGte a1 a2 pos =
  if is_max_min a1 || is_max_min a2 then
    failwith ("max/min can only be used in equality")
  else
    Gte (a1, a2, pos)

and mkNull (v : spec_var) pos = mkEqExp (mkVar v pos) (Null pos) pos

and mkNeqNull (v : spec_var) pos = mkNeqExp (mkVar v pos) (Null pos) pos

and mkNeq a1 a2 pos =
  if is_max_min a1 || is_max_min a2 then
    failwith ("max/min can only be used in equality")
  else
    Neq (a1, a2, pos)

and mkEq_b a1 a2 pos : b_formula=
  (mkEq a1 a2 pos, None)

and mkEq a1 a2 pos : p_formula=
  if is_max_min a1 && is_max_min a2 then
    failwith ("max/min can only appear in one side of an equation")
  else if is_max_min a1 then
    match a1 with
    | Min (a11, a12, _) -> EqMin (a2, a11, a12, pos)
    | Max (a11, a12, _) -> EqMax (a2, a11, a12, pos)
    | _ -> failwith ("Presburger.mkAEq: something really bad has happened")
  else if is_max_min a2 then
    match a2 with
    | Min (a21, a22, _) -> EqMin (a1, a21, a22, pos)
    | Max (a21, a22, _) -> EqMax (a1, a21, a22, pos)
    | _ -> failwith ("Presburger.mkAEq: something really bad has happened")
  else
    Eq (a1, a2, pos)


and mkAnd_x f1 f2 (*b*) pos = 
  if (isConstFalse f1) then f1
  else if (isConstTrue f1) then f2
  else if (isConstFalse f2) then f2
  else if (isConstTrue f2) then f1
  else 
    let rec helper fal fnl = match fal with 
      | Or _ -> join_disjunctions (List.map (fun d->helper d fnl) (split_disjunctions fal))
      | AndList b ->  mkAndList (Label_Pure.merge b [(LO.unlabelled,fnl)])
      | _ -> And (fal,fnl, pos) in
    match no_andl f1 , no_andl f2 with 
    | true, true -> And (f1, f2, pos) 
    (*if b then And (f1, f2, pos) 
      else 	join_disjunctions (Gen.BList.remove_dups_eq equalFormula ((split_disjunctions f1)@(split_disjunctions f2)))*)
    | true, false -> helper f2 f1
    | false, true -> helper f1 f2
    | false, false ->
      match f1,f2 with
      | Or _, _ 
      | _, Or _ ->  
        let lf1 = split_disjunctions f1 in
        let lf2 = split_disjunctions f2 in
        let lrd = List.map (fun c-> List.map (fun d->mkAnd_x d c pos) lf1) lf2 in
        join_disjunctions (List.concat lrd)
      | AndList b1, AndList b2 ->  mkAndList (Label_Pure.merge b1 b2)
      | AndList b, f
      | f, AndList b -> ((*print_string ("this br: "^(!print_formula f1)^"\n"^(!print_formula f2)^"\n");*) mkAndList (Label_Pure.merge b [(LO.unlabelled,f)]))
      | _ -> And (f1, f2, pos)

(*and mkAnd_chk f1 f2 pos = mkAnd_dups f1 f2 false pos

  and mkAnd_x f1 f2 pos = mkAnd_dups f1 f2 true pos*)

(* and mkAnd f1 f2 pos = Debug.DebugEmpty.no_2(\* _loop *\) "pure_mkAnd" !print_formula !print_formula !print_formula (fun _ _-> mkAnd_x f1 f2 pos) f1 f2 *)

and mkAnd f1 f2 pos = mkAnd_x f1 f2 pos


and mkAndList_x b = 
  if (exists_l_snd isConstFalse b) then mkFalse no_pos
  else AndList (Label_Pure.norm (List.filter (fun (_,c)-> not (isConstTrue c)) b))

and mkAndList b = Debug.no_1 "pure_mkAndList" (fun _ -> "") !print_formula (fun _-> mkAndList_x b) b

and and_list_to_and l = match l with
  | [] -> mkTrue no_pos
  | (_,x)::t -> List.fold_left (fun a (_,c)-> mkAnd a c no_pos) x t


(*and or_branches l1 l2 lbl pos=
  let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
  let map_fun branch =
  try 
  let l1 = List.assoc branch l1 in
  try
  let l2 = List.assoc branch l2 in
  (branch, mkOr l1 l2 lbl pos)
  with Not_found -> (branch, mkTrue pos)
  with Not_found -> (branch, mkTrue pos )
  in
  Label_Pure.norm  (List.map map_fun branches)*)

and mkOr_x f1 f2 lbl pos= 
  if (isConstFalse f1) then f2
  else if (isConstTrue f1) then f1
  else if (isConstFalse f2) then f1
  else if (isConstTrue f2) then f2
  else (*match f1, f2 with 
         | AndList l1, AndList l2 -> AndList (or_branches l1 l2 lbl pos)
         | AndList l, f
         | f, AndList l -> AndList (or_branches l [(LO.unlabelled,f)] lbl pos)
         | _ -> *)Or (f1, f2, lbl ,pos)

and mkOr f1 f2 lbl pos = Debug.no_2 "pure_mkOr" !print_formula !print_formula !print_formula (fun _ _ -> mkOr_x f1 f2 lbl pos) f1 f2

and mkStupid_Or_x f1 f2 lbl pos= 
  let or_branches l1 l2 lbl pos=
    let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
    let map_fun branch =
      try 
        let l1 = List.assoc branch l1 in
        try
          let l2 = List.assoc branch l2 in
          (branch, mkOr l1 l2 lbl pos)
        with Not_found -> (branch, mkTrue pos)
      with Not_found -> (branch, mkTrue pos )
    in
    Label_Pure.norm  (List.map map_fun branches) in
  if (isConstFalse f1) then f2
  else if (isConstTrue f1) then f1
  else if (isConstFalse f2) then f1
  else if (isConstTrue f2) then f2
  else match f1, f2 with 
    | AndList l1, AndList l2 -> AndList (or_branches l1 l2 lbl pos)
    | AndList l, f
    | f, AndList l -> AndList (or_branches l [(LO.unlabelled,f)] lbl pos)
    | _ -> Or (f1, f2, lbl ,pos)

and mkStupid_Or f1 f2 lbl pos = Debug.no_2 "pure_mkStupidOr" !print_formula !print_formula !print_formula (fun _ _ -> mkOr_x f1 f2 lbl pos) f1 f2

and mkGtExp (ae1 : exp) (ae2 : exp) pos :formula =
  match (ae1, ae2) with
  | (Var v1, Var v2) ->
    if eq_spec_var (fst v1) (fst v2) then
      mkFalse pos 
    else
      BForm ((Gt (ae1, ae2, pos), None),None)
  | _ ->  BForm ((Gt (ae1, ae2, pos), None),None)

and mkLtExp (ae1 : exp) (ae2 : exp) pos :formula =
  match (ae1, ae2) with
  | (Var v1, Var v2) ->
    if eq_spec_var (fst v1) (fst v2) then
      mkFalse pos 
    else
      BForm ((Lt (ae1, ae2, pos), None),None)
  | _ ->  BForm ((Lt (ae1, ae2, pos), None),None)

and mkLteExp (ae1 : exp) (ae2 : exp) pos :formula =
  BForm ((Lte (ae1, ae2, pos), None),None)

and mkGteExp (ae1 : exp) (ae2 : exp) pos :formula =
  BForm ((Gte (ae1, ae2, pos), None),None)

and mkEqExp (ae1 : exp) (ae2 : exp) pos :formula =
  (* let ae1,ae2 =  *)
  (*   match ae1,ae2 with *)
  (*     | Var (v1,_), IConst(0,l)  *)
  (*           -> ae1,(if (is_otype (type_of_spec_var v1)) then Null no_pos else ae2) *)
  (*     | _ -> ae1,ae2 in *)
  if !Globals.mkeqn_opt_flag then
    match (ae1, ae2) with
    | (Var v1, Var v2) ->
      if eq_spec_var (fst v1) (fst v2) then
        mkTrue pos
      else
        BForm ((Eq (ae1, ae2, pos), None),None)
    | _ -> BForm ((Eq (ae1, ae2, pos), None),None)
  else BForm ((Eq (ae1, ae2, pos), None),None)

and mkNeqExp (ae1 : exp) (ae2 : exp) pos = match (ae1, ae2) with
  | (Var v1, Var v2) ->
    if eq_spec_var (fst v1) (fst v2) then
      mkFalse pos 
    else
      BForm ((Neq (ae1, ae2, pos), None),None)
  | _ ->  BForm ((Neq (ae1, ae2, pos), None),None)

and mkNot_s f :formula = mkNot f None no_pos

and mkNot_dumb f lbl1 pos0:formula = 
  if (!Globals.non_linear_flag) || (not !Globals.allow_norm  && !Globals.allow_inf_qe_coq) then Not (f, lbl1,pos0)
  else 
    match f with
    | BForm (bf,lbl) -> begin
        let (pf,il) = bf in
        match pf with
        | BConst (b, pos) -> BForm ((BConst ((not b), pos), il),lbl)
        | Lt (e1, e2, pos) -> BForm ((Gte (e1, e2, pos), il),lbl)
        | Lte (e1, e2, pos) -> BForm ((Gt (e1, e2, pos), il),lbl)
        | Gt (e1, e2, pos) -> BForm ((Lte (e1, e2, pos), il),lbl)
        | Gte (e1, e2, pos) -> BForm ((Lt (e1, e2, pos), il),lbl)
        | Eq (e1, e2, pos) -> BForm ((Neq (e1, e2, pos), il),lbl)
        | Neq (e1, e2, pos) -> BForm ((Eq (e1, e2, pos), il),lbl)
        | BagIn e -> BForm (((BagNotIn e), il),lbl)
        | BagNotIn e -> BForm (((BagIn e), il),lbl)
        | _ -> Not (f, lbl, pos0)
      end
    | _ -> Not (f, lbl1,pos0)

and mkNot_x f lbl1 pos0 :formula= 
  if no_andl f  then mkNot_dumb f lbl1 pos0
  else 
    match f with
    | And (f1,f2,p) -> mkOr (mkNot f1 lbl1 pos0) (mkNot f2  lbl1 pos0) None p
    | AndList b -> 
      let l = List.map (fun (l,c)-> AndList [(l,Not (c,lbl1,pos0))]) b in
      (match l with 
       | []-> report_error pos0 "cpure mkNot, empty AndList list"
       | x::t-> List.fold_left (fun a c-> mkOr a c lbl1 pos0) x t)
    | Or _ -> 
      let l = List.map (fun c-> mkNot_x c lbl1 pos0) (split_disjunctions f) in
      List.fold_left (fun a c-> mkAnd a c pos0) (List.hd l) (List.tl l)
    | _ -> mkNot_dumb f lbl1 pos0

and mkNot f lbl1 pos0 = Debug.no_1 "mkNot" !print_formula !print_formula (fun _-> mkNot_x f lbl1 pos0) f

and mkEqVar (sv1 : spec_var) (sv2 : spec_var) pos =
  if eq_spec_var sv1 sv2 then
    mkTrue pos
  else
    BForm ((Eq (Var (sv1, pos), Var (sv2, pos), pos), None),None)

and mkEqNull (sv1 : spec_var) (sv2 : spec_var) pos=
  if eq_spec_var sv1 sv2 then
    mkTrue pos
  else
    BForm ((Eq (Var (sv1, pos), Null no_pos, pos), None),None)

and mkGteVar (sv1 : spec_var) (sv2 : spec_var) pos=
  if eq_spec_var sv1 sv2 then
    mkTrue pos
  else
    BForm (((Gte (Var (sv1, pos), Var (sv2, pos), pos)),None), None)

and mkLteVar (sv1 : spec_var) (sv2 : spec_var) pos=
  if eq_spec_var sv1 sv2 then
    mkTrue pos
  else
    BForm (((Lte (Var (sv1, pos), Var (sv2, pos), pos)),None), None)

and mkLtVar (sv1 : spec_var) (sv2 : spec_var) pos=
  if eq_spec_var sv1 sv2 then
    mkFalse pos
  else
    BForm (((Lt (Var (sv1, pos), Var (sv2, pos), pos)),None), None)

and mkNeqVar (sv1 : spec_var) (sv2 : spec_var) pos =
  if eq_spec_var sv1 sv2 then
    mkFalse pos
  else
    BForm ((Neq (Var (sv1, pos), Var (sv2, pos), pos), None),None)

and mkGtVarInt (sv: spec_var) (i : int) pos =
  BForm ((Gt (Var (sv, pos), IConst (i, pos), pos), None),None)

and mkEqVarInt (sv : spec_var) (i : int) pos =
  BForm ((Eq (Var (sv, pos), IConst (i, pos), pos), None),None)

and mkNeqVarInt (sv : spec_var) (i : int) pos =
  BForm ((Neq (Var (sv, pos), IConst (i, pos), pos), None),None)


(*and mkTrue pos l= BForm ((BConst (true, pos)),l)*)

and mkTrue_p pos = BConst (true, pos)

and mkTrue_b pos = (BConst (true, pos),None)

and mkTrue pos =  BForm ((BConst (true, pos), None),None)

and simplify = ref (fun (c:formula) -> mkTrue no_pos)

and oc_hull = ref (fun (c:formula) -> mkTrue no_pos)

and mkFalse pos = BForm ((BConst (false, pos), None),None)

and mkFalse_b pos = (BConst (false, pos), None) 

and mkExists_x (vs : spec_var list) (f : formula) lbel pos = match f with
  | AndList b ->
    let pusher v lf lrest=
      let rl,vl,rf = List.fold_left (fun (al,avs,af) (cl,cvs,cf)-> (x_add LO.comb_norm 2 al cl,avs@cvs, mkAnd af cf pos)) (List.hd lf) (List.tl lf) in
      (rl,vl, Exists (v,rf,lbel,pos))::lrest in
    let lst = List.map (fun (l,c)-> (l,fv c,c)) b in
    let lst1 = List.fold_left (fun lbl v->
        let l1,l2 = List.partition (fun (_,vl,_)-> List.mem v vl) lbl in
        if l1=[] then l2
        else  pusher v l1 l2
        (*let lul, ll = List.partition (fun (lb,_,_)-> LO.is_unlabelled lb) l1 in
          if lul=[] || ll=[] then pusher v l1 l2
          else
          let lrel = split_conjunctions ((fun (_,_,f)-> f) (List.hd lul)) in
          let lrel,lunrel = List.partition (fun c->List.mem v (fv c)) lrel in
          let lrelf = join_conjunctions lrel in
          let lunrelf = join_conjunctions lunrel in
          let lrel = ((fun (l,_,_)-> l)(List.hd ll),fv lrelf, lrelf) in
          let lunrel = (LO.unlabelled, fv lunrelf, lunrelf) in
          pusher v (lrel::ll) (lunrel::l2) *)
      )lst vs in
    let l = List.map (fun (l,_,f)-> (l,f)) lst1 in
    let () = x_ninfo_hp (add_str "l0" (pr_list (pr_pair Label_only.LOne.string_of !print_formula))) l no_pos in
    (* let l = if !Globals.use_baga (\* !Globals.gen_baga_inv *\) *)
    (*   then *)
    (*     List.map (fun ((a,ls) as lbl,f) -> *)
    (*         let new_lbl = *)
    (*           if string_eq a "" then *)
    (*             match ls with *)
    (*             | [(x,ann)] -> if ann = Label_only.LA_Both then (x,[]) else lbl *)
    (*             | _ -> lbl *)
    (*           else lbl *)
    (*         in *)
    (*         (new_lbl,f)) l *)
    (*   else *)
    (*     l *)
    (* in *)
    let () = x_ninfo_hp (add_str "l1" (pr_list (pr_pair Label_only.LOne.string_of !print_formula))) l no_pos in
    AndList (Label_Pure.norm l)
  | Or (f1,f2,lbl,pos) ->
    Or (mkExists_x vs f1 lbel pos, mkExists_x vs f2 lbel pos, lbl, pos)
  (*| And(f1,f2,pos) ->
    let lconj = split_conjunctions f in
    let lrel,lunrel = List.partition (fun c->List.exists (fun v-> List.mem v (fv c)) vs) lconj in
    if lrel=[] then f
    else
    let lrelf = join_conjunctions lrel in
    let lunrelf = join_conjunctions lunrel in
    let lrelf =
    let fvs = fv lrelf in
    let to_push = List.filter (fun c-> mem c fvs) vs in
    List.fold_left (fun a v-> Exists (v,a,lbel,pos)) lrelf to_push in
    mkAnd_dumb lunrelf lrelf pos*)
  | _ ->
    (* let fvs = fv f in
     * let to_push = List.filter (fun c-> mem c fvs) vs in
     * 	List.fold_left (fun a v-> Exists (v,a,lbel,pos)) f to_push *)
    (* Pushing each ex v to the innermost location *)
    let fvs = fv f in
    let vs = List.filter (fun v -> mem v fvs) vs in
    let fl = split_conjunctions f in
    let f_with_fv = List.map (fun f -> (fv f, f)) fl in
    let push_v v f_with_fv =
      let rel_f, nonrel_f = List.partition (fun (fvs, f) -> mem v fvs) f_with_fv in
      let rel_fvs, rel_f = List.split rel_f in
      ((Gen.BList.difference_eq eq_spec_var (List.concat rel_fvs) [v]),
       (Exists (v, join_conjunctions rel_f, lbel, pos)))::nonrel_f
    in join_conjunctions (snd (List.split
                                 ((List.fold_left (fun a v -> push_v v a) f_with_fv vs))))

and mkExists_naive (vs : spec_var list) (f : formula) lbl pos =
  let rec aux vs f lbl pos = 
    match vs with
    | [] -> f
    | v :: rest ->
      let ef = aux rest f lbl pos in
      if mem v (fv ef) then
        Exists (v, ef, lbl, pos)
      else
        ef 
  in
  if vs==[] then f 
  else 
    match f with
    | AndList lst ->
      let lst = List.map (fun (l,f) -> (l,aux vs f lbl pos)) lst in
        AndList lst
    | Or(f1,f2,l,p) ->
      Or(aux vs f1 l pos,aux vs f2 l pos, l,p)
    | _ -> aux vs f lbl pos

and mkExists_gfp (vs : spec_var list) (f : formula) lbl pos =
  let rec aux vs f lbl pos = 
    match vs with
    | [] -> f
    | v :: rest ->
      let ef = aux rest f lbl pos in
      if mem v (fv ef) then
        Exists (v, ef, lbl, pos)
      else
        ef 
  in
  if vs==[] then f 
  else 
    aux vs f lbl pos

and mkExists vs f lbel pos =
  let vs1 = List.filter (fun v -> not(is_rel_all_var v)) vs in
  let () = x_tinfo_hp (add_str "vs(mkExists)" !print_svl) vs no_pos in
  let () = x_tinfo_hp (add_str "vs(filtered rel type)" !print_svl) vs1 no_pos in
  let fn = if false (* !Globals.adhoc_flag_2 *) then mkExists_x else mkExists_naive
  in
  Debug.no_2 "pure_mkExists" !print_svl !print_formula !print_formula (fun _ _ -> fn vs1 f lbel pos) vs1 f

(*and mkExistsBranches (vs : spec_var list) (f : (branch_label * formula )list) lbl pos =  List.map (fun (c1,c2)-> (c1,(mkExists vs c2 lbl pos))) f*)

and mkForall (vs : spec_var list) (f : formula) lbl pos = match vs with
  | [] -> f
  | v :: rest ->
    let ef = mkForall rest f lbl pos in
    if mem v (fv ef) then
      Forall (v, ef, lbl, pos)
    else
      ef

and mkForall_disjs_deep (vs : spec_var list) (f : formula) lbl pos =
  let ps = list_of_disjs f in
  let irr_ps, rele_ps = List.fold_left (fun (r_ls1,r_ls2) p ->
      let svl = fv p in
      let inter = intersect_svl svl vs in
      if inter = [] then (r_ls1@[p], r_ls2)
      else (r_ls1, r_ls2@[(p, inter)])
    ) ([],[]) ps in
  let quan_rele_ps = List.map (fun (p, quans) -> mkForall quans p lbl pos) rele_ps in
  disj_of_list (irr_ps@quan_rele_ps) pos

and dperm_subst_simpl f =
  let comb l1 l2 = l1 @ l2 in
  let rec coll_eq f = match f with
    | And (f1,f2,_) -> comb (coll_eq f1) (coll_eq f2)
    | AndList b -> let l = List.map (fun (_,c)-> coll_eq c) b in List.fold_left comb (List.hd l) (List.tl l)
    | Or _ ->  []
    | Not _ -> []
    | Forall (v,f,_,_)
    | Exists (v,f,_,_)-> coll_eq f
    | BForm ((f,_),_)-> (match f with
        |Eq (Var (v,_),Tsconst (t,_),_)
        |Eq (Tsconst (t,_),Var (v,_),_)-> [(v,t)]
        (*|Eq (Var (v1,_),Var (v2,_),_) -> if (type_of_spec_var v1=Tree_sh) then [([v1;v2],None)] else []*)
        | _ -> []) in
  let rec helper flg lsubs f = match f with
    | Or (f1,f2,l,pos) ->
      let lsubs1 = lsubs @ coll_eq f1 in
      let lsubs2 = lsubs @ coll_eq f2 in
      let f1 = if lsubs1=[] then f1 else helper flg lsubs1 f1  in
      let f2 = if lsubs2=[] then f2 else helper flg lsubs2 f2  in
      if lsubs1<>[] || lsubs2<>[] then mkOr f1 f2 l pos else f
    | And (f1,f2,l)-> if lsubs=[] then f  else mkAnd (helper flg lsubs f1) (helper flg lsubs f2) l
    | AndList b ->    if lsubs=[] then f  else mkAndList (map_l_snd (helper flg lsubs) b)
    | Not (f1,l,pos)->if lsubs=[] then f  else mkNot (helper flg lsubs f1) l pos
    | Forall (v,f1,l,pos) -> if lsubs=[] then f else mkForall [v] (helper flg lsubs f1) l pos
    | Exists (v,f1,l,pos) -> if lsubs=[] then f else mkExists [v] (helper true lsubs f1) l pos
    | BForm ((Eq(e1,e2,p1),p2),p3) -> if not flg then  f
      else
        let fct t = match t with
          | Tsconst (t,_)-> Some t
          | Var (v,_)->
            (try
               Some (snd (List.find (fun (c,_)-> eq_spec_var v c) lsubs))
             with | Not_found -> None)
          | _ -> None in
        let r = match e1,e2 with
          | Var _ ,Add(a1,a2,_)
          | Tsconst _ , Add(a1,a2,_) -> Some (e1,a1,a2)
          | Add(a1,a2,_), Tsconst _
          | Add(a1,a2,_),Var _  -> Some (e2,a1,a2)
          | _ -> None  in
        (match r with
         | None -> f
         | Some (e0,e1,e2) ->
           let t0 = fct e0 in
           let test t r = match t with
             | None -> f
             | Some s -> if Tree_shares.Ts.contains s r then f else mkFalse  no_pos in
           (match fct e1,fct e2 with 
            | None, None -> f
            | None, Some s 
            | Some s, None -> test t0 s
            | Some s1, Some s2 -> if Tree_shares.Ts.can_join s1 s2 then test t0 ( Tree_shares.Ts.join s1 s2) else mkFalse no_pos))
    | _ -> f in
  helper false (coll_eq f) f

(*
  match (e1,e2) with
  | (Null _ ,Null _ ) -> true
  | (Var (v1,_), Var (v2,_)) -> (eq v1 v2)
  | (IConst (v1,_), IConst (v2,_)) -> v1=v2
  | (FConst (v1,_), FConst (v2,_)) -> v1=v2
  | (Div(e1, e2, _), Div(d1, d2, _)) 
  | (Subtract(e1, e2, _), Subtract(d1, d2, _)) -> (eqExp_f eq e1 d1)& (eqExp_f eq e2 d2)
  | (Max (e1,e2,_),Max (d1,d2,_)) 
  | (Min (e1,e2,_),Min (d1,d2,_)) 
  | (Mult (e1, e2, _), Mult(d1, d2, _)) ->
  | (Add (e1,e2,_),Add (d1,d2,_)) -> (eqExp_f eq e1 d1)& (eqExp_f eq e2 d2)  (*((eqExp_f eq e1 d2)&&(eqExp_f eq e2 d1))*)
  | (BagDiff(e1,e2,_),BagDiff (d1,d2,_)) -> ((eqExp_f eq e1 d1)& (eqExp_f eq e2 d2))
  | (Div _, Div _) -> false (* FIX IT *)
  | (Bag (l1,_),Bag (l2,_)) -> if (List.length l1)=(List.length l1) then List.for_all2 (fun a b-> (eqExp_f eq a b)) l1 l2 
  else false
  | (List (l1,_),List (l2,_))
  | (ListAppend (l1,_),ListAppend (l2,_))  -> if (List.length l1)=(List.length l2) then List.for_all2 (fun a b-> (eqExp_f eq a b)) l1 l2 
  else false
  | (ListCons (e1,e2,_),ListCons (d1,d2,_)) -> (eqExp_f eq e1 d1)&&(eqExp_f eq e2 d2)
  | (ListHead (e1,_),ListHead (e2,_))
  | (ListTail (e1,_),ListTail (e2,_))
  | (ListLength (e1,_),ListLength (e2,_))
  | (ListReverse (e1,_),ListReverse (e2,_)) -> (eqExp_f eq e1 e2)
  | _ -> false
*)

and mem (sv : spec_var) (svs : spec_var list) : bool =
  List.exists (fun v -> eq_spec_var sv v) svs

and mem_x fun_eq (sv : spec_var) (svs : spec_var list) : bool =
  List.exists (fun v -> fun_eq sv v) svs

and disjoint (svs1 : spec_var list) (svs2 : spec_var list) =
  List.for_all (fun sv -> not (mem sv svs2)) svs1

and subset (svs1 : spec_var list) (svs2 : spec_var list) =
  List.for_all (fun sv -> mem sv svs2) svs1

and intersect (svs1 : spec_var list) (svs2 : spec_var list) =
  List.filter (fun sv -> mem sv svs2) svs1

and intersect_x fun_eq (svs1 : spec_var list) (svs2 : spec_var list) =
  List.filter (fun sv -> mem_x fun_eq sv svs2) svs1

and intersect_svl x y = intersect x y

and diff_svl_x (svs1 : spec_var list) (svs2 : spec_var list) =
  List.filter (fun sv -> not(mem sv svs2)) svs1

and diff_svl (svs1 : spec_var list) (svs2 : spec_var list) =
  Debug.no_2 "diff_svl" !print_svl !print_svl !print_svl diff_svl_x svs1 svs2

(* same of list_of_conjs *)
and split_conjunctions_x =  function
  | And (x, y, _) -> (split_conjunctions_x x) @ (split_conjunctions_x y)
  | AndList l -> List.map (fun p -> AndList [p]) l
  (* Gen.fold_l_snd split_conjunctions_x l *)
  | z -> [z]

and split_conjunctions f =  
  let pr = !print_formula in
  (* Debug.no_1 "split_conjunctions" pr (pr_list pr) *) split_conjunctions_x f 


and join_conjunctions fl = conj_of_list fl no_pos

(******************)
(* 
   Make a formula from a list of conjuncts, namely
   [F1,F2,..,FN]  ==> F1 & F2 & .. & Fn 
*)
and conj_of_list (fs : formula list) pos : formula =
  match fs with
  | [] -> mkTrue pos
  | x::xs -> List.fold_left (fun a c-> mkAnd a c no_pos) x xs
          (*
            let helper f1 f2 = mkAnd f1 f2 pos in
            List.fold_left helper (mkTrue pos) fs
          *)

(*
   Get a list of disjuncts, namely
   F1 or F2 or .. or Fn ==> [F1,F2,..,FN]
*)
(* 16.04.09 *)
and list_of_disjs (f0 : formula) : formula list =split_disjunctions f0

and disj_of_list (xs : formula list) pos : formula =
  let rec helper xs r = match xs with
    | [] -> r
    | x::xs -> mkOr x (helper xs r) None pos in
  match xs with
  | [] -> mkTrue pos
  | x::xs -> helper xs x

(*
   Get a list of conjuncts, namely
   F1 & F2 & .. & Fn ==> [F1,F2,..,FN]
   TODO : push exists inside where possible..
*)
and list_of_conjs_x (f0 : formula) : formula list = split_conjunctions f0

and list_of_conjs (f0 : formula) : formula list =
  Debug.DebugEmpty.no_1 "list_of_conjs"  !print_formula (pr_list !print_formula) split_conjunctions f0
(*let rec helper f conjs = match f with
  | And (f1, f2, pos) ->
  let tmp1 = helper f2 conjs in
  let tmp2 = helper f1 tmp1 in
  tmp2
  | _ -> f :: conjs
  in
  helper f0 []*)


and split_disjunctions =
  (* split_disjuncts *)
  function
  | Or (x, y, _,_) -> (split_disjunctions x) @ (split_disjunctions y)
  | z -> [z]

(* preserve order of disjunction *)
and join_disjunctions xs = disj_of_list (List.rev xs) no_pos

and no_andl  = function
  | BForm _ | And _ | Not _ | Forall _ | Exists _  -> true
  | Or (f1,f2,_,_) -> no_andl f1 && no_andl f2
  | AndList _ -> false

(* decided to drop zero since same as f_comb e [] *)

let foldr_exp (e:exp) (arg:'a) (f:'a->exp->(exp * 'b) option) 
    (f_args:'a->exp->'a)(f_comb:exp -> 'b list -> 'b) 
  :(exp * 'b) =
  let rec helper (arg:'a) (e:exp) : (exp * 'b)=
    let r =  f arg e  in 
    match r with
    | Some ne -> ne
    | None ->  let new_arg = f_args arg e in 
      let f_comb = f_comb e in match e with
      | Null _ 
      | Var _ 
      | Level _ 
      | IConst _
      | InfConst _ 
      | NegInfConst _
      | AConst _
      | Tsconst _ 
      | Bptriple _ 
      | FConst _ -> (e,f_comb [])
      | Tup2 ((e1,e2),l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Tup2 ((ne1,ne2),l),f_comb[r1;r2])
      | Add (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Add (ne1,ne2,l),f_comb[r1;r2])
      | Subtract (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Subtract (ne1,ne2,l),f_comb[r1;r2])
      | Mult (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Mult (ne1,ne2,l),f_comb[r1;r2])
      | Div (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Div (ne1,ne2,l),f_comb[r1;r2])
      | Max (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Max (ne1,ne2,l),f_comb[r1;r2])
      | Min (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (Min (ne1,ne2,l),f_comb[r1;r2])
      | TypeCast (ty, e1, l) ->
        let (ne1, r1) = helper new_arg e1 in
        (TypeCast(ty, ne1, l), f_comb[r1])
      | Bag (le,l) -> 
        let el=List.map (fun c-> helper new_arg c) le in
        let (el,rl)=List.split el in 
        (Bag (el, l), f_comb rl) 
      | BagUnion (le,l) -> 
        let el=List.map (fun c-> helper new_arg c) le in
        let (el,rl)=List.split el in 
        (BagUnion (el, l), f_comb rl)
      | BagIntersect (le,l) -> 
        let el=List.map (fun c-> helper new_arg c) le in
        let (el,rl)=List.split el in 
        (BagIntersect (el, l), f_comb rl) 
      | BagDiff (e1,e2,l) ->
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (BagDiff (ne1,ne2,l),f_comb[r1;r2])
      | List (e1,l) -> (* List (( List.map (helper new_arg) e1), l)*) 
        let el=List.map (fun c-> helper new_arg c) e1 in
        let (el,rl)=List.split el in 
        (List (el, l), f_comb rl) 
      | ListCons (e1,e2,l) -> 
        let (ne1,r1) = helper new_arg e1 in
        let (ne2,r2) = helper new_arg e2 in
        (ListCons (ne1,ne2,l),f_comb[r1;r2])
      | ListHead (e1,l) -> 
        let (ne1,r1) = helper new_arg e1 in
        (ListHead (ne1,l),f_comb [r1])
      | ListTail (e1,l) -> 
        let (ne1,r1) = helper new_arg e1 in
        (ListTail (ne1,l),f_comb [r1])
      | ListLength (e1,l) -> 
        let (ne1,r1) = helper new_arg e1 in
        (ListLength (ne1,l),f_comb [r1])
      | ListAppend (e1,l) ->  
        let el=List.map (fun c-> helper new_arg c) e1 in
        let (el,rl)=List.split el in 
        (ListAppend (el, l), f_comb rl) 
      | ListReverse (e1,l) -> 
        let (ne1,r1) = helper new_arg e1 in
        (ListReverse (ne1,l),f_comb [r1])
      | Func (id, es, l) ->
        let il,rl = List.split (List.map (fun c-> helper new_arg c) es) in
        (Func (id,il,l), f_comb rl)
      | Template t -> 
        let il1, rl1 = List.split (List.map (helper new_arg) t.templ_args) in
        let il2, rl2 = map_opt_def (None, []) (fun e -> 
            let i, r = helper new_arg e in Some i, [r]) t.templ_body in
        (Template { t with templ_args = il1; templ_body = il2}, f_comb (rl1@rl2))
      | ArrayAt (a, i, l) -> (* An Hoa *)
        let il = List.map (fun c-> helper new_arg c) i in
        let (il, rl) = List.split il in 
        (ArrayAt (a,il,l), f_comb rl)
  in helper arg e

let trans_exp (e:exp) (arg:'a) (f:'a->exp->(exp * 'b) option) 
    (f_args:'a->exp->'a)(f_comb: 'b list -> 'b) 
  :(exp * 'b) =
  foldr_exp e arg f f_args (fun x l -> f_comb l) 

let fold_exp (e: exp) (f: exp -> 'b option) (f_comb: 'b list -> 'b) : 'b =
  let new_f a e = push_opt_val_rev (f e) e in
  snd (trans_exp e () new_f voidf2 f_comb)


let var_list_exp (e:exp) =
  let f_e e =
    match e with
    | Var (v,_) -> Some [v]
    | _ -> None
  in
  fold_exp e f_e List.concat
;;

let const_exp_list_exp (e:exp) =
  let f_e e =
    match e with
    | IConst (i,_) -> Some [i]
    | _ -> None
  in
  fold_exp e f_e List.concat
;;

let rec transform_exp f e  =
  let r =  f e in
  match r with
  | Some ne -> ne
  | None -> match e with
    | Null _
    | Var _
    | Level _
    | IConst _
    | AConst _
    | InfConst _ 
    | NegInfConst _ 
    | Tsconst _
    | Bptriple _
    | FConst _ -> e
    | Tup2 ((e1,e2),l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Tup2 ((ne1,ne2),l)
    | Add (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Add (ne1,ne2,l)
    | Subtract (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Subtract (ne1,ne2,l)
    | Mult (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Mult (ne1,ne2,l)
    | Div (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Div (ne1,ne2,l)
    | Max (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Max (ne1,ne2,l)
    | Min (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      Min (ne1,ne2,l)
    | TypeCast (ty, e1, l) ->
      let ne1 = transform_exp f e1 in
      TypeCast (ty, ne1, l)
    | Bag (le,l) ->
      Bag (List.map (fun c-> transform_exp f c) le, l)
    | BagUnion (le,l) ->
      BagUnion (List.map (fun c-> transform_exp f c) le, l)
    | BagIntersect (le,l) ->
      BagIntersect (List.map (fun c-> transform_exp f c) le, l)
    | BagDiff (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      BagDiff (ne1,ne2,l)
    | List (e1,l) -> List (( List.map (transform_exp f) e1), l)
    | ListCons (e1,e2,l) ->
      let ne1 = transform_exp f e1 in
      let ne2 = transform_exp f e2 in
      ListCons (ne1,ne2,l)
    | ListHead (e1,l) -> ListHead ((transform_exp f e1),l)
    | ListTail (e1,l) -> ListTail ((transform_exp f e1),l)
    | ListLength (e1,l) -> ListLength ((transform_exp f e1),l)
    | ListAppend (e1,l) ->  ListAppend (( List.map (transform_exp f) e1), l)
    | ListReverse (e1,l) -> ListReverse ((transform_exp f e1),l)
    | Func (id, es, l) -> Func (id, (List.map (transform_exp f) es), l)
    | Template t -> Template { t with 
                               templ_args = List.map (transform_exp f) t.templ_args; 
                               templ_body = map_opt (transform_exp f) t.templ_body; }
    | ArrayAt (a, i, l) -> ArrayAt (a, (List.map (transform_exp f) i), l) (* An Hoa *)

let foldr_b_formula (e:b_formula) (arg:'a) f f_args f_comb
(*(f_comb:'b list -> 'b)*) :(b_formula * 'b) =
  let (f_b_formula, f_exp) = f in
  let (f_b_formula_args, f_exp_args) = f_args in
  let (f_b_formula_comb, f_exp_comb) = f_comb in
  let helper (arg:'a) (e:exp) : (exp * 'b)= foldr_exp e arg f_exp f_exp_args f_exp_comb in
  let helper2 (arg:'a) (e:b_formula) : (b_formula * 'b) =
    let r =  f_b_formula arg e in
    match r with
    | Some e1 -> e1
    | None  -> let new_arg = f_b_formula_args arg e in
      let f_comb = f_b_formula_comb e in
      let (pf, annot) = e in
      let (nannot, opt1) = match annot with
        | None -> (None, f_comb [])
        | Some (il, lb, el) ->
          let (nel, opt1) = List.split (List.map (fun e -> helper new_arg e) el) in
          (Some (il, lb, nel), f_comb opt1)
      in
      let (npf, opt2) = let rec helper3 pf = 
                          match pf with
                          | Frm _
                          | BConst _
                          | BVar _ 
                          | XPure _ 
                          | BagMin _ 
                          (* | VarPerm _ (*TO CHECK*) *)
                          | BagMax _ -> (pf,f_comb [])
                          | SubAnn (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (SubAnn (ne1,ne2,l),f_comb[r1;r2])
                          | Lt (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Lt (ne1,ne2,l),f_comb[r1;r2])
                          | Lte (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Lte (ne1,ne2,l),f_comb[r1;r2])
                          | Gt (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Gt (ne1,ne2,l),f_comb[r1;r2])
                          | Gte (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Gte (ne1,ne2,l),f_comb[r1;r2])
                          | Eq (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Eq (ne1,ne2,l),f_comb[r1;r2])
                          | Neq (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (Neq (ne1,ne2,l),f_comb[r1;r2])
                          | EqMax (e1,e2,e3,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            let (ne3,r3) = helper new_arg e3 in
                            (EqMax (ne1,ne2,ne3,l),f_comb[r1;r2;r3])      
                          | EqMin (e1,e2,e3,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            let (ne3,r3) = helper new_arg e3 in
                            (EqMin (ne1,ne2,ne3,l),f_comb[r1;r2;r3])
                          (* bag formulas *)
                          | BagIn (v,e,l)->
                            let (ne1,r1) = helper new_arg e in
                            (BagIn (v,ne1,l),f_comb [r1])
                          | BagNotIn (v,e,l)->
                            let (ne1,r1) = helper new_arg e in
                            (BagNotIn (v,ne1,l),f_comb [r1])
                          | BagSub (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (BagSub (ne1,ne2,l),f_comb[r1;r2])
                          | ListIn (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (ListIn (ne1,ne2,l),f_comb[r1;r2])
                          | ListNotIn (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (ListNotIn (ne1,ne2,l),f_comb[r1;r2])
                          | ListAllN (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (ListAllN (ne1,ne2,l),f_comb[r1;r2])
                          | ListPerm (e1,e2,l) ->
                            let (ne1,r1) = helper new_arg e1 in
                            let (ne2,r2) = helper new_arg e2 in
                            (ListPerm (ne1,ne2,l),f_comb[r1;r2])
                          | RelForm (r, args, l) -> (* An Hoa *)
                            let tmp = List.map (helper new_arg) args in
                            let nargs = List.map fst tmp in
                            let rs = List.map snd tmp in
                            (RelForm (r,nargs,l),f_comb rs)
                          | ImmRel (r, cond, l) -> 
                            let new_ir, rs = helper3 r in
                            (new_ir, rs)
                          | LexVar t_info ->
                            let tmp1 = List.map (helper new_arg) t_info.lex_exp in
                            let n_lex_exp = List.map fst tmp1 in
                            let tmp2 = List.map (helper new_arg) t_info.lex_tmp in
                            let n_lex_tmp = List.map fst tmp2 in
                            let rs = List.map snd (tmp1@tmp2) in
                            (LexVar { t_info with
                                      lex_exp = n_lex_exp; lex_tmp = n_lex_tmp;
                                    }, f_comb rs)
        in helper3 pf 
      in ((npf, nannot), f_comb [opt1; opt2])
  in (helper2 arg e)


let trans_b_formula (e:b_formula) (arg:'a) f
    f_args (f_comb: 'b list -> 'b) :(b_formula * 'b) =
  foldr_b_formula e arg f f_args  ((fun x l -> f_comb l), (fun x l -> f_comb l))

let map_b_formula_arg (bf: b_formula) (arg: 'a) (f_bf, f_e) f_arg : b_formula =
  let trans_func f = (fun a e -> push_opt_void_pair (f a e)) in
  let new_f = trans_func f_bf, trans_func f_e in
  fst (trans_b_formula bf arg new_f f_arg voidf)

let fold_b_formula (e: b_formula) (f_bf, f_e) (f_comb: 'b list -> 'b) : 'b =
  let trans_func func = (fun _ e -> push_opt_val_rev (func e) e) in
  let new_f = trans_func f_bf, trans_func f_e in
  let f_arg = voidf2, voidf2 in
  snd (trans_b_formula e () new_f f_arg f_comb)

let transform_b_formula f (e:b_formula) :b_formula =
  let (f_b_formula, f_exp) = f in
  let r =  f_b_formula e in
  match r with
  | Some e1 -> e1
  | None  ->
    let (pf,il) = e in
    let npf = let rec helper pf = 
                match pf with
                | Frm _
                | BConst _
                | XPure _ (* WN : xpure *)
                | BVar _ 
                | BagMin _ 
                (* | VarPerm _(*TO CHECK*) *)
                | BagMax _ -> pf
                | SubAnn  (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  SubAnn (ne1,ne2,l)
                | Lt (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Lt (ne1,ne2,l)
                | Lte (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Lte (ne1,ne2,l)
                | Gt (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Gt (ne1,ne2,l)
                | Gte (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Gte (ne1,ne2,l)
                | Eq (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Eq (ne1,ne2,l)
                | Neq (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  Neq (ne1,ne2,l)
                | EqMax (e1,e2,e3,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  let ne3 = transform_exp f_exp e3 in
                  EqMax (ne1,ne2,ne3,l)   
                | EqMin (e1,e2,e3,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  let ne3 = transform_exp f_exp e3 in
                  EqMin (ne1,ne2,ne3,l)
                (* bag formulas *)
                | BagIn (v,e,l)->
                  let ne1 = transform_exp f_exp e in
                  BagIn (v,ne1,l)
                | BagNotIn (v,e,l)->
                  let ne1 = transform_exp f_exp e in
                  BagNotIn (v,ne1,l)
                | BagSub (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  BagSub (ne1,ne2,l)
                | ListIn (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  ListIn (ne1,ne2,l)
                | ListNotIn (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  ListNotIn (ne1,ne2,l)
                | ListAllN (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  ListAllN (ne1,ne2,l)
                | ListPerm (e1,e2,l) ->
                  let ne1 = transform_exp f_exp e1 in
                  let ne2 = transform_exp f_exp e2 in
                  ListPerm (ne1,ne2,l)
                | RelForm (r, args, l) -> (* An Hoa *)
                  let nargs = List.map (transform_exp f_exp) args in
                  RelForm (r,nargs,l)
                | ImmRel (r, cond, l) -> (* An Hoa *)
                  let r = helper r in
                  ImmRel (r,cond,l)
                | LexVar t_info -> 
                  let nle = List.map (transform_exp f_exp) t_info.lex_exp in
                  let nlt = List.map (transform_exp f_exp) t_info.lex_tmp in
                  LexVar { t_info with lex_exp = nle; lex_tmp = nlt; }
      in helper pf
    in (npf,il)

(*
type: formula ->
  'a ->
  ('a -> formula -> (Label_Pure.exp_ty * 'b) option) *
  ('a -> b_formula -> (b_formula * 'b) option) *
  ('a -> exp -> (exp * 'b) option) ->
  ('a -> formula -> 'a) * ('a -> b_formula -> 'a) * ('a -> exp -> 'a) ->
  (formula -> 'b list -> 'b) * (b_formula -> 'b list -> 'b) *
  (exp -> 'b list -> 'b) -> Label_Pure.exp_ty * 'b
*)
let foldr_formula (e: formula) (arg: 'a) f f_arg f_comb : (formula * 'b) =
  let f_formula, f_b_formula, f_exp = f in
  let f_formula_arg, f_b_formula_arg, f_exp_arg = f_arg in
  let f_formula_comb, f_b_formula_comb, f_exp_comb = f_comb in
  let foldr_b_f (arg: 'a) (e: b_formula): (b_formula * 'b) =
    foldr_b_formula e arg (f_b_formula, f_exp) (f_b_formula_arg, f_exp_arg) (f_b_formula_comb, f_exp_comb)
  in
  let rec foldr_f (arg: 'a) (e: formula): (formula * 'b) =
    let r = f_formula arg e in
    match r with
    | Some e1 -> e1
    | None ->
      let new_arg = f_formula_arg arg e in
      let f_comb = f_formula_comb e in
      match e with
      | BForm (bf, lbl) ->
        let new_bf, r1 = foldr_b_f new_arg bf in
        (BForm (new_bf, lbl), f_comb [r1])
      | And (f1, f2, l) ->
        let nf1, r1 = foldr_f new_arg f1 in
        let nf2, r2 = foldr_f new_arg f2 in
        (mkAnd nf1 nf2 l, f_comb [r1; r2])
      | AndList b -> 
        let r1,r2 = map_l_snd_res (foldr_f new_arg) b in
        (AndList r1, f_comb r2)
      | Or (f1, f2, lbl, l) ->
        let nf1, r1 = foldr_f new_arg f1 in
        let nf2, r2 = foldr_f new_arg f2 in
        (Or (nf1, nf2, lbl, l), f_comb [r1; r2])
      | Not (f1, lbl, l) ->
        let nf1, r1 = foldr_f new_arg f1 in
        (Not (nf1, lbl, l), f_comb [r1])
      | Forall (sv, f1, lbl, l) ->
        let nf1, r1 = foldr_f new_arg f1 in
        (Forall (sv, nf1, lbl, l), f_comb [r1])
      | Exists (sv, f1, lbl, l) ->
        let nf1, r1 = foldr_f new_arg f1 in
        (Exists (sv, nf1, lbl, l), f_comb [r1])
  in foldr_f arg e

(* f = (f_f, f_bf, f_e) and
   f_f: 'a -> formula -> (formula * 'b) option
   f_bf: 'a -> b_formula -> (b_formula * 'b) option
   f_e: 'a -> exp -> (exp * 'b) option
   f_arg : ('a -> formula -> 'a) * ('a -> b_formula -> 'a) * ('a -> exp -> 'a) 
   f_comb : ('b list -> 'b) 
*)
let trans_formula (e: formula) (arg: 'a) f f_arg f_comb : (formula * 'b) =
  let f_comb = (fun x l -> f_comb l), 
               (fun x l -> f_comb l),
               (fun x l -> f_comb l)
  in
  (* let () = print_string ("[cpure.ml] trans_formula: \n") in *)
  foldr_formula e arg f f_arg f_comb

(* compute a result from formula with argument
 * f_f: 'a -> formula -> 'b option
 * f_bf: 'a -> b_formula -> 'b option
 * f_e: 'a -> exp -> 'b option
*)
let fold_formula_arg (e: formula) (arg: 'a) (f_f, f_bf, f_e) f_arg (f_comb: 'b list -> 'b) : 'b =
  let trans_func func = (fun a e -> push_opt_val_rev (func a e) e) in
  let new_f = trans_func f_f, trans_func f_bf, trans_func f_e in
  (* let () = print_string ("[cpure.ml] fold_formula_arg: \n") in *)

  snd (trans_formula e arg new_f f_arg f_comb)

(* compute a result from formula without passing an argument
 * f_f: formula -> 'b option
 * f_bf: b_formula -> 'b option
 * f_e: exp -> 'b option
*)
let fold_formula (e: formula) (f_f, f_bf, f_e) (f_comb: 'b list -> 'b) : 'b =
  let trans_func func = (fun _ e -> push_opt_val_rev (func e) e) in
  let new_f = trans_func f_f, trans_func f_bf, trans_func f_e in
  let f_arg = voidf2, voidf2, voidf2 in

  (* let () = print_string ("[cpure.ml] fold_formula: \n") in *)

  snd (trans_formula e () new_f f_arg f_comb)

(* map functions to formula with argument
   type: formula ->
   'a ->
   f_f : ('a -> formula -> formula option) * 
   f_bf: ('a -> b_formula -> b_formula option) *
   f_e: ('a -> exp -> exp option) ->
   ('a -> formula -> 'a) * ('a -> b_formula -> 'a) * ('a -> exp -> 'a) ->
   formula
*)

let map_formula_arg (e: formula) (arg: 'a) (f_f, f_bf, f_e) f_arg : formula =
  let trans_func f = (fun a e -> push_opt_void_pair (f a e)) in
  let new_f = trans_func f_f, trans_func f_bf, trans_func f_e in

  (* let () = print_string ("[cpure.ml]  map_formula_arg: \n") in *)

  fst (trans_formula e arg new_f f_arg voidf)

(* map functions to formula without argument
 * f_f: formula -> formula option
 * f_bf: b_formula -> b_formula option
 * f_e: exp -> exp option
*)
let map_formula (e: formula) (f_f, f_bf, f_e) : formula =
  let trans_func f = (fun _ e -> push_opt_void_pair (f e)) in
  let new_f = trans_func f_f, trans_func f_bf, trans_func f_e in
  let f_arg = idf2, idf2, idf2 in

  (* let () = print_string ("[cpure.ml]  map_formula: \n") in *)

  fst (trans_formula e () new_f f_arg voidf)

let rec transform_formula f (e:formula) :formula = 
  let (_ , _, f_formula, f_b_formula, f_exp) = f in
  let r =  f_formula e in 
  match r with
  | Some e1 -> e1
  | None  -> match e with
    | BForm (b1,b2) -> 
      BForm ((transform_b_formula (f_b_formula, f_exp) b1) ,b2)
    | And (e1,e2,l) -> 
      let ne1 = transform_formula f e1 in
      let ne2 = transform_formula f e2 in
      mkAnd ne1 ne2 l       
    | AndList b -> AndList (map_l_snd (transform_formula f) b) 
    | Or (e1,e2,fl, l) -> 
      let ne1 = transform_formula f e1 in
      let ne2 = transform_formula f e2 in
      Or (ne1,ne2,fl,l)       
    | Not (e,fl,l) ->
      let ne1 = transform_formula f e in
      Not (ne1,fl,l)
    | Forall (v,e,fl,l) ->
      let ne = transform_formula f e in
      Forall(v,ne,fl,l)
    | Exists (v,e,fl,l) ->
      let ne = transform_formula f e in
      Exists(v,ne,fl,l)

let transform_formula f (e:formula) :formula =
  Debug.no_1 "transform_formula" 
    !print_formula
    !print_formula
    (fun _ -> transform_formula f e ) e

(* End of Transform functions *)

let rec is_member_pure (f:formula) (p:formula):bool =
  let y = split_conjunctions p in
  List.exists (fun c-> equalFormula f c) y

and is_neg_of_consj f : bool =
  match f with
  | Not (p1,_,_) -> begin
      match p1 with
      | And (_,_,_) -> true
      | _ -> false
    end
  | _ -> false

and is_disjunct f : bool =
  match f with
  | Or(_,_,_,_) -> true
  | _ -> false

and equalFormula_f (eq:spec_var -> spec_var -> bool) (f01:formula)(f02:formula):bool =
  let pr = !print_formula in
  Debug.no_2 "equalFormula_f" pr pr string_of_bool (fun _ _ -> equalFormula_f_x eq f01 f02) f01 f02

(*limited, should use equal_formula, equal_b_formula, eq_exp instead*)
and equalFormula_f_x (eq:spec_var -> spec_var -> bool) (f01:formula)(f02:formula):bool =
  let rec helper f1 f2=
    match (f1,f2) with
    | ((BForm (b1,_)),(BForm (b2,_))) -> equalBFormula_f eq  b1 b2
    | ((Not (b1,_,_)),(Not (b2,_,_))) -> helper b1 b2
    | (Or(f1, f2, _,_), Or(f3, f4, _,_))
    | (And(f1, f2, _), And(f3, f4, _)) -> ((helper f1 f3) && (helper f2 f4))
                                          || ((helper f1 f4) && (helper f2 f3))
    | AndList b1, AndList b2 ->
      if (List.length b1)= List.length b2
      then List.for_all2 (fun (l1,c1)(l2,c2)-> LO.compare l1 l2 = 0 && helper c1 c2) b1 b2
      else false
    | (Exists(sv1, f1, _,_), Exists(sv2, f2, _,_))
    | (Forall(sv1, f1,_, _), Forall(sv2, f2, _,_)) -> (eq sv1 sv2) && (helper f1 f2)
    | _ -> false
  in
  let ps1 = list_of_conjs f01 in
  let ps2 = list_of_conjs f02 in
  let l1 = List.length ps1 in
  if l1 == List.length ps2 then
    if l1<=2 then
      helper f01 f02
    else
      let xps1,rems1=List.partition is_xpure ps1 in
      let xps2,rems2=List.partition is_xpure ps2 in
      try
        if List.for_all2 helper rems1 rems2 then
          let get_xp f=
            match f with
            | BForm ((XPure xp1,_),_) -> xp1
            | _ -> report_error no_pos "cpure.equalFormula_f: should be xpure_view"
          in
          (*simple sort*)
          let sort_fn xp1 xp2 = String.compare xp1.xpure_view_name xp2.xpure_view_name in
          let xps11 = List.sort sort_fn (List.map get_xp xps1) in
          let xps21 = List.sort sort_fn (List.map get_xp xps2) in
          List.for_all2 eq_xpure_view xps11 xps21
        else false
      with _ -> false
  else false

and equalBFormula_f (eq:spec_var -> spec_var -> bool) (f1:b_formula)(f2:b_formula):bool =
  let (pf1,_) = f1 in
  let (pf2,_) = f2 in
  match (pf1,pf2) with
  | (BConst(c1, _), BConst(c2, _)) -> c1 = c2
  | (XPure xp1, XPure xp2) -> eq_xpure_view xp1 xp2
  | (BVar(sv1, _), BVar(sv2, _)) -> (eq sv1 sv2)
  | (Lte(IConst(i1, _), e2, _), Lt(IConst(i3, _), e4, _)) -> i1=i3+1 && eqExp_f eq e2 e4
  | (Lte(e1, IConst(i2, _), _), Lt(e3, IConst(i4, _), _)) -> i2=i4-1 && eqExp_f eq e1 e3
  | (Lt(IConst(i1, _), e2, _), Lte(IConst(i3, _), e4, _)) -> i1=i3-1 && eqExp_f eq e2 e4
  | (Lt(e1, IConst(i2, _), _), Lte(e3, IConst(i4, _), _)) -> i2=i4+1 && eqExp_f eq e1 e3
  | (Gte(IConst(i1, _), e2, _), Gt(IConst(i3, _), e4, _)) -> i1=i3-1 && eqExp_f eq e2 e4
  | (Gte(e1, IConst(i2, _), _), Gt(e3, IConst(i4, _), _)) -> i2=i4+1 && eqExp_f eq e1 e3
  | (Gt(IConst(i1, _), e2, _), Gte(IConst(i3, _), e4, _)) -> i1=i3+1 && eqExp_f eq e2 e4
  | (Gt(e1, IConst(i2, _), _), Gte(e3, IConst(i4, _), _)) -> i2=i4-1 && eqExp_f eq e1 e3
  | (Lte(e1, e2, _), Gt(e4, e3, _))
  | (Lte(e1, e2, _), Gte(e4, e3, _))
  | (Gte(e1, e2, _), Lte(e4, e3, _))
  | (Gt(e1, e2, _), Lte(e4, e3, _))
  | (Gte(e1, e2, _), Lt(e4, e3, _))
  | (Lt(e1, e2, _), Gte(e4, e3, _))
  | (SubAnn(e1, e2, _), SubAnn(e3, e4, _))
  | (Lte(e1, e2, _), Lte(e3, e4, _))
  | (Gt(e1, e2, _), Gt(e3, e4, _))
  | (Gte(e1, e2, _), Gte(e3, e4, _))
  | (Lt(e1, e2, _), Lt(e3, e4, _)) -> (eqExp_f eq e1 e3) && (eqExp_f eq e2 e4)
  | (Neq(e1, e2, _), Neq(e3, e4, _))
  | (Eq(e1, e2, _), Eq(e3, e4, _)) -> ((eqExp_f eq e1 e3) && (eqExp_f eq e2 e4)) || ((eqExp_f eq e1 e4) && (eqExp_f eq e2 e3))
  | (EqMax(e1, e2, e3, _), EqMax(e4, e5, e6, _))
  | (EqMin(e1, e2, e3, _), EqMin(e4, e5, e6, _))  -> (eqExp_f eq e1 e4) && ((eqExp_f eq e2 e5) && (eqExp_f eq e3 e6)) || ((eqExp_f eq e2 e6) && (eqExp_f eq e3 e5))
  | (BagIn(sv1, e1, _), BagIn(sv2, e2, _))
  | (BagNotIn(sv1, e1, _), BagNotIn(sv2, e2, _)) -> (eq sv1 sv2) && (eqExp_f eq e1 e2)
  | (ListIn(e1, e2, _), ListIn(d1, d2, _))
  | (ListNotIn(e1, e2, _), ListNotIn(d1, d2, _)) -> (eqExp_f eq e1 d1) && (eqExp_f eq e2 d2)
  | (ListAllN(e1, e2, _), ListAllN(d1, d2, _)) -> (eqExp_f eq e1 d1) && (eqExp_f eq e2 d2)
  | (ListPerm(e1, e2, _), ListPerm(d1, d2, _)) -> (eqExp_f eq e1 d1) && (eqExp_f eq e2 d2)
  | (BagMin(sv1, sv2, _), BagMin(sv3, sv4, _))
  | (BagMax(sv1, sv2, _), BagMax(sv3, sv4, _)) -> (eq sv1 sv3) && (eq sv2 sv4)
  | (BagSub(e1, e2, _), BagSub(e3, e4, _)) -> (eqExp_f eq e1 e3) && (eqExp_f eq e2 e4)
  | (RelForm (r1,args1,_), RelForm (r2,args2,_)) -> (eq_spec_var r1 r2) && (eqExp_list_f eq args1 args2)
  | _ -> false
          (*
            match (f1,f2) with
            | ((BVar v1),(BVar v2))-> (eq (fst v1) (fst v2))
            | ((Lte (v1,v2,_)),(Lte (w1,w2,_)))
            | ((Lt (v1,v2,_)),(Lt (w1,w2,_)))-> (eqExp_f eq w1 v1)&&(eqExp_f eq w2 v2)
            | ((Neq (v1,v2,_)) , (Neq (w1,w2,_)))
            | ((Eq (v1,v2,_)) , (Eq (w1,w2,_))) -> ((eqExp_f eq w1 v1)&&(eqExp_f eq w2 v2))|| ((eqExp_f eq w1 v2)&&(eqExp_f eq w2 v1))
            | ((BagIn (v1,e1,_)),(BagIn (v2,e2,_)))
            | ((BagNotIn (v1,e1,_)),(BagNotIn (v2,e2,_))) -> (eq v1 v2)&&(eqExp_f eq e1 e2)
            | ((ListIn (e1,e2,_)),(ListIn (d1,d2,_)))
            | ((ListNotIn (e1,e2,_)),(ListNotIn (d1,d2,_))) -> (eqExp_f eq e1 d1)&&(eqExp_f eq e2 d2)
            | ((ListAllN (e1,e2,_)),(ListAllN (d1,d2,_))) -> (eqExp_f eq e1 d1)&&(eqExp_f eq e2 d2)
            | ((ListPerm (e1,e2,_)),(ListPerm (d1,d2,_))) -> (eqExp_f eq e1 d1)&&(eqExp_f eq e2 d2)
            | ((BagMax (v1,v2,_)),(BagMax (w1,w2,_))) 
            | ((BagMin (v1,v2,_)),(BagMin (w1,w2,_))) -> (eq v1 w1)&& (eq v2 w2)
            | _ -> false
          *)

and eqExp_f (eq:spec_var -> spec_var -> bool) (e1:exp)(e2:exp):bool =
  (* Debug.no_2 "eqExp_f" !print_exp !print_exp string_of_bool *) (eqExp_f_x eq) e1 e2 

and eqExp_f_x (eq:spec_var -> spec_var -> bool) (e1:exp)(e2:exp):bool =
  let rec helper e1 e2 =
    match (e1, e2) with
    | (Null(_), Null(_)) -> true
    | (Null(_), Var(sv, _)) -> (name_of_spec_var sv) = "null"
    | (Var(sv, _), Null(_)) -> (name_of_spec_var sv) = "null"
    | (Var(sv1, _), Var(sv2, _)) -> (eq sv1 sv2)
    | (Level(sv1, _), Level(sv2, _)) -> (eq sv1 sv2)
    | (IConst(i1, _), IConst(i2, _)) -> i1 = i2
    | (FConst(f1, _), FConst(f2, _)) -> f1 = f2
    | (AConst(a1, _), AConst(a2, _)) -> a1 = a2
    | (Tsconst(t1,_), Tsconst(t2,_)) -> Tree_shares.Ts.eq t1 t2
    | (Subtract(e11, e12, _), Subtract(e21, e22, _))
    | (Tup2 ((e11,e12),_), Tup2  ((e21,e22),_))
    | (Max(e11, e12, _), Max(e21, e22, _))
    | (Min(e11, e12, _), Min(e21, e22, _))
    | (Add(e11, e12, _), Add(e21, e22, _)) -> (helper e11 e21) && (helper e12 e22)
    | (Mult(e11, e12, _), Mult(e21, e22, _)) -> (helper e11 e21) && (helper e12 e22)
    | (Div(e11, e12, _), Div(e21, e22, _)) -> (helper e11 e21) && (helper e12 e22)
    | (Bag(e1, _), Bag(e2, _))
    | (BagUnion(e1, _), BagUnion(e2, _))
    | (BagIntersect(e1, _), BagIntersect(e2, _)) -> (eqExp_list_f eq e1 e2)
    | (BagDiff(e1, e2, _), BagDiff(e3, e4, _)) -> (helper e1 e3) && (helper e2 e4)
    | (List (l1, _), List (l2, _))
    | (ListAppend (l1, _), ListAppend (l2, _)) -> if (List.length l1) = (List.length l2) then List.for_all2 (fun a b-> (helper a b)) l1 l2 
      else false
    | (ListCons (e1, e2, _), ListCons (d1, d2, _)) -> (helper e1 d1) && (helper e2 d2)
    | (ListHead (e1, _), ListHead (e2, _))
    | (ListTail (e1, _), ListTail (e2, _))
    | (ListLength (e1, _), ListLength (e2, _))
    | (ListReverse (e1, _), ListReverse (e2, _)) -> (helper e1 e2)
    | (ArrayAt (a1, i1, _), ArrayAt (a2, i2, _)) -> (eq a1 a2) && (eqExp_list_f eq i1 i2)
    | _ -> false
  in helper e1 e2

and eqExp_list_f (eq:spec_var -> spec_var -> bool) (e1 : exp list) (e2 : exp list) : bool =
  let rec eq_exp_list_helper (e1 : exp list) (e2 : exp list) = match e1 with
    | [] -> true
    | h :: t -> (List.exists (fun c -> eqExp_f eq h c) e2) && (eq_exp_list_helper t e2)
  in
  (eq_exp_list_helper e1 e2) && (eq_exp_list_helper e2 e1)

and remove_dupl_conj_eq (cnjlist:formula list):formula list = Gen.BList.remove_dups_eq equalFormula cnjlist

and equalFormula (f1:formula) (f2:formula):bool = equalFormula_f eq_spec_var  f1 f2

and equalBFormula (f1:b_formula)(f2:b_formula):bool = equalBFormula_f eq_spec_var  f1 f2

and eqExp (f1:exp) (f2:exp):bool = eqExp_f eq_spec_var  f1 f2

(* build relation from list of expressions, for example a,b,c < d,e, f *)
and build_relation relop alist10 alist20 lbl pos =
  let prt = fun al -> List.fold_left (fun r a -> r ^ "; " ^ (!print_exp a)) "" al in
  Debug.no_2 "build_relation" prt prt (!print_formula) (fun al1 al2 -> build_relation_x relop al1 al2 lbl pos) alist10 alist20

and build_relation_x relop alist10 alist20 lbl pos =
  let rec helper1 ae alist =
    (* print_endline "inside helper1"; *)
    let a = List.hd alist in
    let rest = List.tl alist in
    (* let check_upper r e ub pos = if ub>1 then r else  Eq (e,(Null no_pos),pos) in *)
    (* let check_lower r e lb pos = if lb>0 then Neq (e,(Null no_pos),pos) else r in *)
    let rec tt relop ae a pos = 
      let r = (relop ae a pos) in
      r in
    (* match r with *)
    (*   | Lte (e1,e2,l)  *)
    (*   | Gte (e2,e1,l) ->  *)
    (*         ( match e1,e2 with *)
    (*           | Var (v,_), IConst(i,l) -> if (is_otype (type_of_spec_var v)) then check_upper r e1 (i+1) l else r *)
    (*           | IConst(i,l), Var (v,_) -> if (is_otype (type_of_spec_var v)) then check_lower r e2 (i-1) l else r *)
    (*           | _ -> r) *)
    (*   | Gt (e1,e2,l)  *)
    (*   | Lt (e2,e1,l) ->  *)
    (*         ( match e1,e2 with *)
    (*           | Var (v,_), IConst(i,l) -> if (is_otype (type_of_spec_var v)) then check_lower r e1 i l else r *)
    (*           | IConst(i,l), Var (v,_) -> if (is_otype (type_of_spec_var v)) then check_upper r e2 i l else r *)
    (*           | _ -> r) *)
    (*   | Eq (e1,e2,l) -> *)
    (*         ( match e1,e2 with *)
    (*           | Var (v,_), IConst(0,l) -> if (is_otype (type_of_spec_var v)) then Eq (e1,(Null no_pos),pos) else r *)
    (*           | IConst(0,l), Var (v,_) -> if (is_otype (type_of_spec_var v)) then Eq (e2,(Null no_pos),pos) else r *)
    (*           | _ -> r) *)
    (*   | Neq (e1,e2,l) -> *)
    (*         ( match e1,e2 with *)
    (*           | Var (v,_), IConst(0,l) -> if (is_otype (type_of_spec_var v)) then Neq (e1,(Null no_pos),pos) else r *)
    (*           | IConst(0,l), Var (v,_) -> if (is_otype (type_of_spec_var v)) then Neq (e2,(Null no_pos),pos) else r *)
    (*           | _ -> r) *)
    (*   | _ -> r in   *)
    (* print_endline "before tt"; *)
    let tmp = BForm (((tt relop ae a pos), None),lbl) in
    if Gen.is_empty rest then
      tmp
    else
      let tmp1 = helper1 ae rest in
      let tmp2 = mkAnd tmp tmp1 pos in
      tmp2 in
  let rec helper2 alist1 alist2 =
    (* print_endline "inside helper2"; *)
    let a = List.hd alist1 in
    let rest = List.tl alist1 in
    let tmp = helper1 a alist2 in
    if Gen.is_empty rest then
      tmp
    else
      let tmp1 = helper2 rest alist2 in
      let tmp2 = mkAnd tmp tmp1 pos in
      tmp2 in
  if List.length alist10 = 0 || List.length alist20 = 0 then
    failwith ("build_relation: zero-length list")
  else
    helper2 alist10 alist20
(* utility functions *)


and are_same_types (t1 : typ) (t2 : typ) = match t1 with
  | Named c1 -> begin match t2 with
      (* | _ -> false *)
      | Named c2 -> c1 = c2 || c1 = "" || c2 = ""
      | _ -> false (* An Hoa *)
    end
  | Array (et1, _) -> begin match t2 with 
      | Array (et2, _) -> are_same_types et1 et2
      | _ -> false  
    end
  | _ -> t1 = t2

and name_of_type (t : typ) : ident = 
  string_of_typ t
(* match t with *)
(*   | Int -> "int" *)
(*   | Bool -> "boolean" *)
(*   | Void -> "void" *)
(*   | Float -> "float" *)
(*   | (TVar i) -> "TVar["^(string_of_int i)^"]" *)
(*   | (BagT t) -> "bag("^(name_of_type (t))^")" *)
(*   | Globals.List -> "list" *)
(*   | Named c -> c *)
(*   | Array (et, _) -> name_of_type et ^ "[]" (\* An Hoa *\) *)

and pos_of_exp (e : exp) = match e with
  | Null p 
  | Var (_, p) 
  | Level (_, p)
  | IConst (_, p) 
  | InfConst (_,p)
  | NegInfConst (_,p)
  | AConst (_, p) 
  | FConst (_, p) 
  | Tsconst (_, p)
  | Tup2 (_,p)
  | Bptriple (_,p)
  | Add (_, _, p) 
  | Subtract (_, _, p) 
  | Mult (_, _, p) 
  | Div (_, _, p) 
  | Max (_, _, p) 
  | Min (_, _, p)
  | TypeCast(_, _, p)
  | Bag (_, p) 
  | BagUnion (_, p) 
  | BagIntersect (_, p) 
  | BagDiff (_, _, p) 
  | List (_, p) 
  | ListAppend (_, p) 
  | ListCons (_, _, p) 
  | ListHead (_, p) 
  | ListTail (_, p) 
  | ListLength (_, p) 
  | ListReverse (_, p) 
  | Func (_,_,p)
  | ArrayAt (_, _, p) -> p (* An Hoa *)
  | Template t -> t.templ_pos

and pos_of_b_formula (b: b_formula) = 
  let (p, _) = b in
  match p with
  | Frm (_, p) -> p
  | LexVar l_info -> l_info.lex_loc
  | SubAnn (_, _, p) -> p
  | BConst (_, p) -> p
  | XPure x -> x.xpure_view_pos
  | BVar (_, p) -> p
  | Lt (_, _, p) -> p
  | Lte (_, _, p) -> p
  | Gt (_, _, p) -> p
  | Gte (_, _, p) -> p
  | Eq (_, _, p) -> p
  | Neq (_, _, p) -> p
  | EqMax (_, _, _, p) -> p
  | EqMin (_, _, _, p) -> p
  (* bag formulas *)
  | BagIn (_, _, p) -> p
  | BagNotIn (_, _, p) -> p
  | BagSub (_, _, p) -> p
  | BagMin (_, _, p) -> p
  | BagMax (_, _, p) -> p
  (* list formulas *)
  | ListIn (_, _, p) -> p
  | ListNotIn (_, _, p) -> p
  | ListAllN (_, _, p) -> p
  | ListPerm (_, _, p) -> p
  | ImmRel (_, _, p) 
  | RelForm (_, _, p) -> p
(* | VarPerm (_,_,p) -> p *)

and pos_of_formula (f: formula) =
  match f with
  | BForm (b, _) -> pos_of_b_formula b
  | And (_, _, p) -> p
  | Or (_, _, _, p) -> p
  | Not (_, _, p) -> p
  | Forall (_, _, _, p) -> p
  | Exists (_, _, _, p) -> p
  | AndList l -> match l with | x::_ -> pos_of_formula (snd x) | _-> no_pos

(*used by error explanation*)    
and list_pos_of_formula f rs: loc list=
  match f with
  | BForm (bf , _) -> rs @ [pos_of_b_formula bf]
  | And (f1, f2, l) -> (list_pos_of_formula f2 (list_pos_of_formula f1 rs))
  | AndList b -> List.fold_left (fun a (_,b)-> list_pos_of_formula b a) rs b
  | Or (f1, f2, _, l)-> let rs1 = (list_pos_of_formula f1 rs) in
    (list_pos_of_formula f2 rs1)
  | Not (f,_, l) -> rs @ [l]
  | Forall (_, f,_, l) -> rs @ [l]
  | Exists (_, f,_, l) -> rs @ [l]

and subst_pos_pformula p pf= match pf with
  | Frm (sv,_) -> Frm (sv,p)
  | LexVar l_info -> LexVar {l_info with lex_loc=p}
  | SubAnn (e1, e2, _) -> SubAnn (e1, e2, p)
  | BConst (b,_) -> BConst (b,p)
  | XPure x -> XPure {x with xpure_view_pos = p}
  | BVar (sv, _) -> BVar (sv, p)
  | Lt (e1, e2, _) -> Lt (e1, e2, p)
  | Lte (e1, e2, _) -> Lte (e1, e2, p)
  | Gt (e1, e2, _) -> Gt (e1, e2, p)
  | Gte (e1, e2, _) -> Gte (e1, e2, p)
  | Eq (e1, e2, _) -> Eq (e1, e2, p)
  | Neq (e1, e2, _) -> Neq (e1, e2, p)
  | EqMax (e1, e2,e3, _) -> EqMax (e1, e2,e3, p)
  | EqMin (e1, e2,e3, _) -> EqMin (e1, e2,e3, p)
  | BagIn (sv, e, _) -> BagIn (sv, e, p)
  | BagNotIn (sv, e, _) -> BagNotIn (sv, e, p)
  | BagSub(e1, e2, _) -> BagSub (e1, e2, p)
  | BagMin (sv1, sv2, _) -> BagMin (sv1, sv2, p)
  | BagMax (sv1, sv2, _) -> BagMax (sv1, sv2, p)
  | ListIn (e1, e2, _) -> ListIn (e1, e2, p)
  | ListNotIn (e1, e2, _) -> ListNotIn (e1, e2, p)
  | ListAllN (e1, e2, _) -> ListAllN (e1, e2, p)
  | ListPerm (e1, e2, _) -> ListPerm (e1, e2, p)
  | RelForm (id, el, _) -> RelForm (id, el, p)
  | ImmRel (id, cond, _) -> ImmRel (id, cond, p)
(* | VarPerm (t,ls,_) -> VarPerm (t,ls,p) *)

and  subst_pos_bformula p (pf, a) =  (subst_pos_pformula p pf, a)

and subst_pos_formula p f = match f with
  | BForm (bf, ofl) -> BForm (subst_pos_bformula p bf, ofl)
  | And (f1, f2, _) ->  And (subst_pos_formula p f1, subst_pos_formula p f2, p)
  | AndList b -> AndList (map_l_snd (subst_pos_formula p) b)
  | Or (f1, f2, ofl, _) ->  Or (subst_pos_formula p f1, subst_pos_formula p f2, ofl, p)
  | Not (f, ofl, _) ->  Not (subst_pos_formula p f, ofl, p)
  | Forall (sv, f, ofl, _) -> Forall (sv,subst_pos_formula p f, ofl, p)
  | Exists (sv, f, ofl, _) -> Exists (sv,subst_pos_formula p f, ofl, p)

(* pre : _<num> *)
and fresh_old_name_x (s: string):string = 
  let slen = (String.length s) in
  let ri = 
    try  
      let n = (String.rindex s '_') in
      (* let () = print_endline ((string_of_int n)) in *)
      let l = (slen-(n+1)) in
      if (l==0) then slen-1
      else 
        let tr = String.sub s (n+1) (slen-(n+1)) in
        (* let () = int_of_string tr in *)
        (* let () = print_endline ((string_of_int n)^tr^"##") in *)
        n
    with  _ -> slen in
  let n = ((String.sub s 0 ri) ^ (fresh_trailer ())) in
  (*let () = print_string ("init name: "^s^" new name: "^n ^"\n") in*)
  n

and fresh_old_name s =
  Debug.no_1 "fresh_old_name" pr_id pr_id fresh_old_name_x s

and fresh_perm_var () = SpecVar(Tree_sh, fresh_old_name "perm",Unprimed)

and fresh_spec_var (sv : spec_var) =
  let old_name = name_of_spec_var sv in
  let name = fresh_old_name old_name in
  (*--- 09.05.2000 *)
  (*let () = (print_string ("\n[cpure.ml, line 521]: fresh name = " ^ name ^ "!!!!!!!!!!!\n\n")) in*)
  (*09.05.2000 ---*)
  let t = type_of_spec_var sv in
  SpecVar (t, name, Unprimed) (* fresh names are unprimed *)

and fresh_thread_var () =
  let old_name = "tid" in
  let name = fresh_old_name old_name in
  (*--- 09.05.2000 *)
  (*let () = (print_string ("\n[cpure.ml, line 521]: fresh name = " ^ name ^ "!!!!!!!!!!!\n\n")) in*)
  (*09.05.2000 ---*)
  let t = thread_typ in
  SpecVar (t, name, Unprimed) (* fresh names are unprimed *)

and fresh_spec_vars (svs : spec_var list) = List.map fresh_spec_var svs

and fresh_spec_var_prefix s (sv : spec_var) =
  let old_name = s^"_"^name_of_spec_var sv in
  let name = fresh_old_name old_name in
  let t = type_of_spec_var sv in
  SpecVar (t, name, Unprimed) (* fresh names are unprimed *)

and fresh_spec_var_ann ?old_name:(on="inf_ann") () =
  let old_name = on in
  let name = fresh_old_name old_name in
  let t = AnnT in
  SpecVar (t, name, Unprimed) (* fresh ann var *)

and fresh_spec_vars_ann (svs : spec_var list) = List.map (fun _ -> fresh_spec_var_ann ()) svs

and fresh_spec_var_rel () =
  let old_name = "R_" in
  let name = fresh_old_name old_name in
  let t = RelT[] in
  SpecVar (t, name, Unprimed) (* fresh rel var *)

and fresh_spec_vars_prefix s (svs : spec_var list) = List.map (fresh_spec_var_prefix s) svs

(* Nondeterministic Variables *)
(* 
 * Check if a variable's value is nondeterminstic in a formula
 * assumption: given nondeterministic variables in formula are indicated by 
 * relation whose name starting by "nondet" string
 * For example: check_non_determinism "c" f
 *        with f = (v_bool) & nondet_Bool(b) & c=b.
 * Then b is given as non-deterministic var.
 *)
and nondet_prefix = "nondet"

and is_nondet_sv sv = 
  let name = name_of_sv sv in
  if (String.length name >= 6) then
    let prefix = String.lowercase (String.sub name 0 6) in
    eq_str prefix nondet_prefix
  else false

and is_nondet_rel bf = 
  match (fst bf) with
  | RelForm (sv, _, _) -> is_nondet_sv sv
  | _ -> false

and check_non_determinism_x (var_name: ident) (f: formula) =
  (* collect nondet variables *)
  let collect_nondet_vars f = (
    let nondet_svs = ref [] in
    let (fh, fm) = (fun _ -> None), (fun _ -> None) in
    let (ff, fe) = (fun _ -> None), (fun e -> Some e) in
    let fb bf = (match (fst bf) with
        | RelForm (sv, args, _) -> (
            if (is_nondet_sv sv) then (
              let args_svs = List.concat (List.map afv args) in
              nondet_svs := remove_dups_svl (!nondet_svs @ args_svs);
            );
            (* let name = name_of_sv sv in                                 *)
            (* if (String.length name >= 6) then (                         *)
            (*   let prefix = String.lowercase (String.sub name 0 6) in    *)
            (*   if (eq_str prefix nondet_prefix) then (                   *)
            (*     let args_svs = List.concat (List.map afv args) in       *)
            (*     nondet_svs := remove_dups_svl (!nondet_svs @ args_svs); *)
            (*   )                                                         *)
            (* );                                                          *)
            Some bf
          )
        | _ -> Some bf
      ) in
    (* what is this for? side-effects *)
    let todo_var = transform_formula (fh, fm, ff, fb, fe) f in
    !nondet_svs
  ) in
  let nondet_svs = collect_nondet_vars f in
  if (List.exists (fun x -> eq_str (name_of_sv x) var_name) nondet_svs) then true
  else (
    let simp_f = !simplify f in
    (* check iff there is connection between var_name and nondet-vars through simp_pf *)
    let rec collect_related_vars vars = (
      let related_vars = ref vars in
      let (fh, fm) = (fun _ -> None), (fun _ -> None) in
      let (ff, fe) = (fun _ -> None), (fun e -> Some e) in
      let fb b = (
        let svs = bfv b in
        let common_svs = intersect_svl svs !related_vars in
        if (List.length common_svs > 0) then (
          (* Debug.tinfo_hprint (add_str "common_svs" (pr_list !print_sv)) common_svs no_pos; *)
          (* Debug.tinfo_hprint (add_str "svs" (pr_list !print_sv)) svs no_pos; *)
          related_vars := remove_dups_svl (!related_vars @ svs);
          (* Debug.tinfo_hprint (add_str "related_vars" (pr_list !print_sv)) !related_vars no_pos; *)
        );
        None
      ) in
      let todo_unknown = transform_formula (fh, fm, ff, fb, fe) simp_f in
      if (List.length !related_vars) <= (List.length vars) then vars
      else collect_related_vars !related_vars
    ) in
    let simp_svs = fv simp_f in
    try 
      let origin_var = List.find (fun x -> eq_str (name_of_sv x) var_name) simp_svs in
      let related_vars = collect_related_vars [origin_var] in
      let related_nondet_svs = intersect_svl nondet_svs related_vars in
      (* x_tinfo_hp (add_str "check var" pr_id) v no_pos;                                         *)
      (* x_tinfo_hp (add_str "f" !print_formula) f no_pos;                                        *)
      (* x_tinfo_hp (add_str "nondet_svs" (pr_list !print_sv)) nondet_svs no_pos;                 *)
      (* x_tinfo_hp (add_str "sim_f" !print_formula) simp_f no_pos;                               *)
      (* x_tinfo_hp (add_str "related_vars" (pr_list !print_sv)) related_vars no_pos;             *)
      (* x_tinfo_hp (add_str "related_nondet_svs" (pr_list !print_sv)) related_nondet_svs no_pos; *)
      (List.length related_nondet_svs != 0)
    with _ -> false
  )

and check_non_determinism (var_name: ident) (f: formula) =
  let pr_v = (add_str "var_name" pr_id) in
  let pr_f = (add_str "f" !print_formula) in
  let pr_res = (add_str "res" string_of_bool) in
  Debug.no_2 "check_non_determinism" pr_v pr_f pr_res
    (fun _ _ -> check_non_determinism_x var_name f) var_name f

and has_nondet_cond f =  
  let f_b bf = 
    let pf, _ = bf in
    match pf with
    | BVar _
    | Lt _
    | Lte _
    | Gt _
    | Gte _
    | Eq _
    | Neq _ ->
      let fv = bfv bf in
      Some (List.exists (fun v -> check_non_determinism (name_of_spec_var v) f) fv)
    | _ -> Some false
  in
  let or_list = List.fold_left (||) false in
  fold_formula f (nonef, f_b, nonef) or_list

and eq_nondet_rel r1 r2 = 
  match r1, r2 with
  | RelForm (sv1, _, p1), RelForm (sv2, _, p2) ->
    if (is_nondet_sv sv1) && (is_nondet_sv sv2) then
      eq_loc p1 p2
    else false
  | _ -> false

and collect_nondet_rel f = 
  let f_bf bf =
    if is_nondet_rel bf then Some [(fst bf)]
    else None
  in
  fold_formula f (nonef, f_bf, nonef) List.concat

and collect_nondet_vars f = 
  let f_bf bf =
    match (fst bf) with
    | RelForm (sv, args, _) -> 
      if is_nondet_sv sv 
      then Some (List.concat (List.map afv args)) 
      else None
    | _ -> None 
  in
  fold_formula f (nonef, f_bf, nonef) List.concat

(* End of Nondeterministic Variables *)

(******************************************************************************************************************
   	                                                                                                           22.05.2008
   	                                                                                                           Utilities for equality testing
 ******************************************************************************************************************)

and normalize_add e  =  
  let rec lin e = match e with 
    | Add(e1,e2,_) -> 
      let l1,l2 = lin e1 in
      let r1,r2 = lin e2 in
      r1@l1, r2@l2
    | Tsconst (t,_) -> [t],[]
    | IConst _
    | FConst _
    | AConst _
    | _ ->  [],[e] in
  let c,rest = lin e in
  if c=[] then e
  else 
    try		
      let r = List.fold_left (fun a c-> 
          if Tree_shares.Ts.can_join a c then Tree_shares.Ts.join a c else raise Not_found) (List.hd c) (List.tl c) in
      List.fold_left (fun a c-> Add (a,c,no_pos)) (Tsconst (r,no_pos)) rest 
    with | Not_found -> e

and eq_spec_var_list (sv1 : spec_var list) (sv2 : spec_var list) =
  let rec eq_spec_var_list_helper (sv1 : spec_var list) (sv2 : spec_var list) = match sv1 with
    | [] -> true
    | h :: t -> (List.exists (fun c -> eq_spec_var h c) sv2) && (eq_spec_var_list_helper t sv2)
  in
  (eq_spec_var_list_helper sv1 sv2) && (eq_spec_var_list_helper sv2 sv1)

and remove_dups_spec_var_list vl = remove_dups_svl vl

and remove_spec_var (sv : spec_var) (vars : spec_var list) =
  List.filter (fun v -> not (eq_spec_var sv v)) vars

and is_anon_var (SpecVar (_,n,p):spec_var) : bool = 
  Ipure.is_anon_ident (n,p)
(* ((String.length n) > 5) && ((String.compare (String.sub n 0 5) "Anon_") == 0) *)

(* substitution *)

and subst_var_list_avoid_capture fr t svs =
  let st1 = List.combine fr t in
  let svs1 = subst_var_list st1 svs in
  svs1

(* renaming seems redundant
   and subst_var_list_avoid_capture fr t svs =
   let fresh_fr = fresh_spec_vars fr in
   let st1 = List.combine fr fresh_fr in
   let st2 = List.combine fresh_fr t in
   let svs1 = subst_var_list st1 svs in
   let svs2 = subst_var_list st2 svs1 in
   svs2
*)

and subst_var_list sst (svs : spec_var list) = subst_var_list_par sst svs

(* filter does not support multiple occurrences of domain 
   and subst_var_list sst (svs : spec_var list) = match svs with
   | sv :: rest ->
   let new_vars = subst_var_list sst rest in
   let new_sv = match List.filter (fun st -> fst st = sv) sst with
   | [(fr, t)] -> t
   | _ -> sv in
   new_sv :: new_vars
   | [] -> []
*)

and subst_var_list_par sst (svs : spec_var list) = match svs with
  | sv :: rest ->
    let new_vars = subst_var_list sst rest in
    let new_sv = subs_one sst sv in 
    new_sv :: new_vars
  | [] -> []

(* The intermediate fresh variables seem redundant. *)
(*and subst_avoid_capture (fr : spec_var list) (t : spec_var list) (f : formula) =
  let fresh_fr = fresh_spec_vars fr in
  let st1 = List.combine fr fresh_fr in
  let st2 = List.combine fresh_fr t in
  let f1 = subst st1 f in
  let f2 = subst st2 f1 in
  f2*)
and subst_avoid_capture (fr : spec_var list) (t : spec_var list) (f : formula) =
  Debug.no_3 "[cpure]subst_avoid_capture"
    !print_svl
    !print_svl
    !print_formula
    !print_formula
    subst_avoid_capture_x fr t f

and subst_avoid_capture_x (fr : spec_var list) (t : spec_var list) (f : formula) =
  try 
    let st1 = List.combine fr t in
    (* let f2 = subst st1 f in *) 
    (* changing to a parallel substitution below *)
    let f2 = par_subst st1 f in 
    f2
  with _ -> failwith (x_loc ^ "[subst_avoid_capture]: Cannot combine fr and t")

and subst (sst : (spec_var * spec_var) list) (f : formula) : formula = apply_subs sst f
(* match sst with *)
(* | s::ss -> subst ss (apply_one s f) 				(\* applies one substitution at a time *\) *)
(* | [] -> f *)

(*LDK ???*) 
and subst_var (fr, t) (o : spec_var) = 
  if eq_spec_var fr o then t
  else o

(* should not use = since type of spec_var may have been different *)
and subst_var_par (sst:(spec_var * spec_var) list) (o : spec_var) : spec_var = 
  let rec helper sst o= match sst with
    | [] -> o
    | (v1,v2)::t -> helper t (if eq_spec_var o v1 then v2 else o) in
  helper sst o
      (*
        try 
        let (_,v2) = List.find (fun (v1,_) -> eq_spec_var o v1) sst in
        v2
      (* List.assoc o sst *)
        with _ -> o*)

and subst_one_var_list s l = List.map (subst_var s) l

and par_subst sst f = apply_subs sst f

and subst_term_ann sst ann =
  map_term_ann (apply_subs sst) (e_apply_subs sst) ann

and apply_subs (sst : (spec_var * spec_var) list) (f : formula) : formula = match f with
  | BForm (bf,lbl) -> BForm ((b_apply_subs sst bf),lbl)
  | And (p1, p2, pos) -> And (apply_subs sst p1,
                              apply_subs sst p2, pos)
  | Or (p1, p2, lbl,pos) -> Or (apply_subs sst p1,
                                apply_subs sst p2, lbl, pos)
  | Not (p, lbl, pos) -> Not (apply_subs sst p, lbl, pos)
  | Forall (v, qf,lbl, pos) ->
    let sst = diff sst v in
    if (var_in_target v sst) then
      let fresh_v = fresh_spec_var v in
      Forall (fresh_v, apply_subs sst (apply_subs [(v, fresh_v)] qf), lbl, pos)
    else Forall (v, apply_subs sst qf, lbl, pos)
  | Exists (v, qf, lbl, pos) ->
    let sst = diff sst v in
    if (var_in_target v sst) then
      let fresh_v = fresh_spec_var v in
      Exists  (fresh_v, apply_subs sst (apply_subs [(v, fresh_v)] qf), lbl, pos)
    else Exists (v, apply_subs sst qf, lbl, pos)
  | AndList b -> AndList (map_l_snd (apply_subs sst) b)


and apply_subs_all (sst : (spec_var * spec_var) list) (f : formula) : formula = match f with
  | BForm (bf,lbl) -> BForm ((b_apply_subs sst bf),lbl)
  | And (p1, p2, pos) -> And (apply_subs_all sst p1, apply_subs_all sst p2, pos)
  | Or (p1, p2, lbl,pos) -> Or (apply_subs_all sst p1, apply_subs_all sst p2, lbl, pos)
  | Not (p, lbl, pos) -> Not (apply_subs_all sst p, lbl, pos)
  | Forall (v, qf,lbl, pos)  ->  Forall (subs_one sst v, apply_subs_all sst qf, lbl, pos)
  | Exists (v, qf, lbl, pos) ->  Exists (subs_one sst v, apply_subs_all sst qf, lbl, pos)
  | AndList b -> AndList (map_l_snd (apply_subs_all sst) b)

(* cannot change to a let, why? *)
and diff (sst : (spec_var * 'b) list) (v:spec_var) : (spec_var * 'b) list
  = List.filter (fun (a,_) -> not(eq_spec_var a v)) sst

and var_in_target v sst = List.fold_left (fun curr -> fun (_,t) -> curr || (eq_spec_var t v)) false sst

(*subst everything excluding VarPerm*)
and b_apply_subs sst bf =
  let pr = !print_b_formula in
  Debug.no_1 "b_apply_subs" pr 
    pr (fun _ -> b_apply_subs_x sst bf) bf

and b_apply_subs_x sst bf =
  let (pf,sl) = bf in
  let npf = let rec helper pf =
              match pf with
              | Frm (fv, pos) -> Frm (subs_one sst fv, pos)
              | BConst _ -> pf
              | BVar (bv, pos) -> BVar (subs_one sst bv, pos)
              | XPure x -> XPure {x with 
                                  xpure_view_node=map_opt (subs_one sst) x.xpure_view_node;
                                  xpure_view_arguments=List.map (subs_one sst) x.xpure_view_arguments;
                                 } 
              | Lt (a1, a2, pos) -> Lt (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | Lte (a1, a2, pos) -> Lte (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | Gt (a1, a2, pos) -> Gt (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | Gte (a1, a2, pos) -> Gte (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | SubAnn (a1, a2, pos) -> SubAnn (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | Eq (a1, a2, pos) -> Eq (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | Neq (a1, a2, pos) -> Neq (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | EqMax (a1, a2, a3, pos) -> 
                EqMax (e_apply_subs sst a1, e_apply_subs sst a2, e_apply_subs sst a3, pos)
              | EqMin (a1, a2, a3, pos) -> 
                EqMin (e_apply_subs sst a1, e_apply_subs sst a2, e_apply_subs sst a3, pos)
              | BagIn (v, a1, pos) -> BagIn (subs_one sst v, e_apply_subs sst a1, pos)
              | BagNotIn (v, a1, pos) -> BagNotIn (subs_one sst v, e_apply_subs sst a1, pos)
              (* is it ok?... can i have a set of boolean values?... don't think so... *)
              | BagSub (a1, a2, pos) -> BagSub (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | BagMax (v1, v2, pos) -> BagMax (subs_one sst v1, subs_one sst v2, pos)
              | BagMin (v1, v2, pos) -> BagMin (subs_one sst v1, subs_one sst v2, pos)
              (* | VarPerm (ct,ls,pos) ->                    *)
              (*     let ls1 = List.map (subs_one sst) ls in *)
              (*     VarPerm (ct,ls1,pos)                    *)
              | ListIn (a1, a2, pos) -> ListIn (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | ListNotIn (a1, a2, pos) -> ListNotIn (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | ListAllN (a1, a2, pos) -> ListAllN (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | ListPerm (a1, a2, pos) -> ListPerm (e_apply_subs sst a1, e_apply_subs sst a2, pos)
              | RelForm (r, args, pos) -> RelForm (subs_one sst r, e_apply_subs_list sst args, pos) (* An Hoa *)
              | ImmRel (r, cond, pos) -> ImmRel (helper r, cond, pos) (* An Hoa *)
              (* | RelForm (r, args, pos) -> RelForm (r, e_apply_subs_list sst args, pos) (\* An Hoa *\) *)
              | LexVar t_info -> 
                LexVar { t_info with
                         lex_ann = map_term_ann (apply_subs sst) (e_apply_subs sst) t_info.lex_ann;
                         lex_exp = e_apply_subs_list sst t_info.lex_exp;
                         lex_tmp = e_apply_subs_list sst t_info.lex_tmp; } 
    in helper pf
  in
  (* Slicing: Add the inferred linking variables into sl field *)
  (* We also restore the prior inferred information            *)
  (* let infer_lvar_enabled = !do_slicing && !infer_lvar_slicing in *)
  let infer_lvar_enabled = (not !dis_slc_ann) && !infer_lvar_slicing in
  let fv = bfv bf in
  let inf_lv = 
    if infer_lvar_enabled then
      match pf with
      | Eq (_, _, pos) ->
        (* Find all fv of bf that do not appear in linking_var_tbl *)
        (* If only one var like this then it is also a linking var *)
        begin let res = List.find_all (fun v1 ->
            try
              let v2 = List.assoc v1 sst in
              (* not (Hashtbl.find !linking_var_tbl (name_of_spec_var v2)) *)
              not (List.mem (name_of_spec_var v2) !linking_var_tbl)
            with Not_found -> true 
          ) fv in
          match res with
          | r::[] -> [r]
          | _ -> []
        end
      | _ -> []
    else [] 
  in 
  (* Restore prior inferred linking variables *)
  let pri_lv =
    if infer_lvar_enabled then
      List.fold_left (fun a (v1, v2) ->
          (* let () = print_endline ("V1: " ^ (!print_sv v1)) in                                                        *)
          (* let () = print_endline ("V2: " ^ (!print_sv v2)) in                                                        *)
          (* let () = print_endline ("BF: " ^ (!print_b_formula bf)) in                                                 *)
          (* let () = print_endline ("C1: " ^ (string_of_bool (Gen.BList.mem_eq eq_spec_var v1 fv))) in                 *)
          (* let () = print_endline ("C2: " ^ (string_of_bool (Hashtbl.mem !linking_var_tbl (name_of_spec_var v2)))) in *)
          (* let () = print_endline ("C2: " ^ (string_of_bool (List.mem (name_of_spec_var v2) !linking_var_tbl))) in    *)
          if (Gen.BList.mem_eq eq_spec_var v1 fv) &&
             (* (Hashtbl.mem !linking_var_tbl (name_of_spec_var v2))  *)
             (List.mem (name_of_spec_var v2) !linking_var_tbl)
          then a @ [v2]
          else a
        ) [] sst
    else [] 
  in
  (* print_endline ("PRI LV: " ^ (pr_list !print_sv pri_lv)); *)
  let inf_sl = match inf_lv @ pri_lv with
    | [] -> None
    | _ -> 
      Some (false, fresh_int (), List.map (fun v -> mkVar v no_pos) (inf_lv @ pri_lv))
  in
  let nsl = match sl with
    | None -> inf_sl
    | Some (il, lbl, le) -> 
      let inf_le = match inf_sl with
        | None -> []
        | Some (_, _, le) -> le 
      in Some (il, lbl, inf_le @ List.map (fun e ->
          (* With a substitution (v1, v2),      *)
          (* if v1 is a linking variable        *)
          (* then v2 is also a linking variable *)
          let () = 
            if infer_lvar_enabled then
              match e with
              | Var (SpecVar _ as v1, _) ->
                (try
                   let v2 = List.assoc v1 sst in
                   (* print_endline ("ADD LV: " ^ (!print_sv v2)); *)
                   (* Hashtbl.add !linking_var_tbl (name_of_spec_var v2) true *)
                   linking_var_tbl := (name_of_spec_var v2)::!linking_var_tbl
                 with Not_found -> ()) 
              | _ -> () 
            else () in 
          e_apply_subs sst e) le)
  in (npf,nsl)

(* and subs_one sst v = List.fold_left (fun old -> fun (fr,t) -> if (eq_spec_var fr v) then t else old) v sst  *)

and subs_one sst v = 
  let rec helper sst v = match sst with
    | [] -> v
    | (fr,t)::sst -> if (eq_spec_var fr v) then t else (helper sst v)
  in helper sst v

and e_apply_subs sst e = match e with
  | Null _ | IConst _ | FConst _ | AConst _ | InfConst _ | NegInfConst _ |Tsconst _ -> e
  | Bptriple ((ec,et,ea),pos) ->
    Bptriple ((subs_one sst ec,
               subs_one sst et,
               subs_one sst ea),pos)
  | Tup2 ((e1,e2),pos) ->
    Tup2 ((e_apply_subs sst e1,
           e_apply_subs sst e2),pos)
  | Var (sv, pos) -> Var (subs_one sst sv, pos)
  | Level (sv, pos) -> Level (subs_one sst sv, pos)
  | Add (a1, a2, pos) -> normalize_add (Add (e_apply_subs sst a1, e_apply_subs sst a2, pos))
  | Subtract (a1, a2, pos) -> Subtract (e_apply_subs sst  a1, e_apply_subs sst a2, pos)
  | Mult (a1, a2, pos) -> Mult (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | Div (a1, a2, pos) -> Div (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | Max (a1, a2, pos) -> Max (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | Min (a1, a2, pos) -> Min (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | TypeCast (t, a, pos) -> TypeCast (t, e_apply_subs sst a, pos)
  | Bag (alist, pos) -> Bag ((e_apply_subs_list sst alist), pos)
  | BagUnion (alist, pos) -> BagUnion ((e_apply_subs_list sst alist), pos)
  | BagIntersect (alist, pos) -> BagIntersect ((e_apply_subs_list sst alist), pos)
  | BagDiff (a1, a2, pos) -> BagDiff (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | List (alist, pos) -> List (e_apply_subs_list sst alist, pos)
  | ListAppend (alist, pos) -> ListAppend (e_apply_subs_list sst alist, pos)
  | ListCons (a1, a2, pos) -> ListCons (e_apply_subs sst a1, e_apply_subs sst a2, pos)
  | ListHead (a, pos) -> ListHead (e_apply_subs sst a, pos)
  | ListTail (a, pos) -> ListTail (e_apply_subs sst a, pos)
  | ListLength (a, pos) -> ListLength (e_apply_subs sst a, pos)
  | ListReverse (a, pos) -> ListReverse (e_apply_subs sst a, pos)
  | Func (a, i, pos) -> Func (subs_one sst a, e_apply_subs_list sst i, pos)
  | ArrayAt (a, i, pos) -> ArrayAt (subs_one sst a, e_apply_subs_list sst i, pos)
  (* Template: Do not substitute into unknowns *)
  | Template t -> Template { t with 
                             templ_args = List.map (e_apply_subs sst) t.templ_args; 
                             templ_body = map_opt (e_apply_subs sst) t.templ_body; }

and e_apply_subs_list_x sst alist = List.map (e_apply_subs sst) alist

and e_apply_subs_list sst alist = 
  let pr = pr_list (pr_pair !print_sv !print_sv) in
  let pr2 = pr_list !print_exp in
  Debug.no_2 "e_apply_subs_list" pr pr2 pr2 e_apply_subs_list_x sst alist

(* TODO : these methods must be made obsolete *)
and b_apply_one s bf = b_apply_subs [s] bf
and apply_one s f = apply_subs [s] f 


and b_subst_x (zip: (spec_var * spec_var) list) (bf:b_formula) :b_formula = 
  b_apply_subs zip bf
(* List.fold_left (fun a c-> b_apply_one c a) bf zip *)

and b_subst (zip: (spec_var * spec_var) list) (bf:b_formula) :b_formula =
  let pr = pr_list (pr_pair !print_sv !print_sv) in
  let pr2 = !print_b_formula in
  Debug.no_2 "b_subst" pr pr2 pr2 b_subst_x zip bf

and e_apply_one_spec_var (fr, t) sv = if eq_spec_var sv fr then t else sv

and e_apply_one (fr, t) e = match e with
  | Null _ | IConst _ | InfConst _ | NegInfConst _ | FConst _ | AConst _ | Tsconst _ -> e
  | Bptriple ((ec,et,ea),pos) ->
    Bptriple ((e_apply_one_spec_var (fr, t) ec,
               e_apply_one_spec_var (fr, t) et,
               e_apply_one_spec_var (fr, t) ea),pos)
  | Tup2 ((e1,e2),pos) ->
    Tup2 ((e_apply_one (fr, t) e1,
           e_apply_one (fr, t) e2),pos)
  | Var (sv, pos) -> Var ((if eq_spec_var sv fr then t else sv), pos)
  | Level (sv, pos) -> Level ((if eq_spec_var sv fr then t else sv), pos)
  | Add (a1, a2, pos) -> normalize_add (Add (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos))
  | Subtract (a1, a2, pos) -> Subtract (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | Mult (a1, a2, pos) -> Mult (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | Div (a1, a2, pos) -> Div (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | Max (a1, a2, pos) -> Max (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | Min (a1, a2, pos) -> Min (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | TypeCast (ty, a, pos) -> TypeCast (ty, e_apply_one (fr, t) a, pos)
  | Bag (alist, pos) -> Bag (e_apply_one_list (fr, t) alist, pos)
  | BagUnion (alist, pos) -> BagUnion (e_apply_one_list (fr, t) alist, pos)
  | BagIntersect (alist, pos) -> BagIntersect (e_apply_one_list (fr, t) alist, pos)
  | BagDiff (a1, a2, pos) -> BagDiff (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | List (alist, pos) -> List (e_apply_one_list (fr, t) alist, pos)
  | ListAppend (alist, pos) -> ListAppend (e_apply_one_list (fr, t) alist, pos)
  | ListCons (a1, a2, pos) -> ListCons (e_apply_one (fr, t) a1, e_apply_one (fr, t) a2, pos)
  | ListHead (a, pos) -> ListHead (e_apply_one (fr, t) a, pos)
  | ListTail (a, pos) -> ListTail (e_apply_one (fr, t) a, pos)
  | ListLength (a, pos) -> ListLength (e_apply_one (fr, t) a, pos)
  | ListReverse (a, pos) -> ListReverse (e_apply_one (fr, t) a, pos)
  | Func (a, i, pos) -> Func ((if eq_spec_var a fr then t else a), e_apply_one_list (fr, t) i, pos)
  | ArrayAt (a, i, pos) -> ArrayAt ((if eq_spec_var a fr then t else a), e_apply_one_list (fr, t) i, pos) (* An Hoa CHECK: BUG DETECTED must compare fr and a, in case we want to replace a[i] by a'[i] *)
  | Template tp -> Template { tp with 
                              templ_args = List.map (e_apply_one (fr, t)) tp.templ_args; 
                              templ_body = map_opt (e_apply_one (fr, t)) tp.templ_body; }

and e_apply_one_list (fr, t) alist = match alist with
  |[] -> []
  |a :: rest -> (e_apply_one (fr, t) a) :: (e_apply_one_list (fr, t) rest)


and subst_term_avoid_capture (sst : (spec_var * exp) list) (f : formula) : formula =
  let f2 = subst_term_par sst f in
  f2

and subst_term (sst : (spec_var * exp) list) (f : formula) : formula = match sst with
  | s :: ss -> subst_term ss (apply_one_term s f)
  | [] -> f

and subst_term_par (sst : (spec_var * exp) list) (f : formula) : formula = 
  apply_par_term sst f

(* wasn't able to make diff/diff_term polymorphic! how come? *)

and diff_term (sst : (spec_var * exp) list) (v:spec_var) : (spec_var * exp) list
  = List.filter (fun (a,_) -> not(eq_spec_var a v)) sst

and apply_par_term (sst : (spec_var * exp) list) f = match f with
  | BForm (bf,lbl) -> BForm (b_apply_par_term sst bf , lbl)
  | And (p1, p2, pos) -> And (apply_par_term sst p1, apply_par_term sst p2, pos)
  | Or (p1, p2,lbl, pos) -> Or (apply_par_term sst p1, apply_par_term sst p2, lbl, pos)
  | Not (p, lbl, pos) -> Not (apply_par_term sst p, lbl, pos)
  | Forall (v, qf, lbl, pos) ->
    let sst = diff_term sst v in
    if (var_in_target_term v sst) then
      let fresh_v = fresh_spec_var v in
      Forall (fresh_v, apply_par_term sst (apply_subs [(v, fresh_v)] qf), lbl, pos)
    else if sst==[] then f else 
      Forall (v, apply_par_term sst qf, lbl, pos)
  | Exists (v, qf, lbl, pos) ->
    let sst = diff_term sst v in
    if (var_in_target_term v sst) then
      let fresh_v = fresh_spec_var v in
      Exists  (fresh_v, apply_par_term sst (apply_subs [(v, fresh_v)] qf), lbl, pos)
    else if sst==[] then f else 
      Exists  (v, apply_par_term sst qf, lbl, pos)
  | AndList b-> AndList (map_l_snd (apply_par_term sst) b)

and var_in_target_term v sst = List.fold_left (fun curr -> fun (_,t) -> curr || (is_member v t)) false sst

and is_member v t = let vl=afv t in List.fold_left (fun curr -> fun nv -> curr || (eq_spec_var v nv)) false vl

and b_apply_par_term (sst : (spec_var * exp) list) bf =
  let (pf,il) = bf in
  let npf = let rec helper pf = 
              match pf with
              | Frm (fv, pos) ->
                if List.exists (fun (fr,_) -> eq_spec_var fv fr) sst   then
                  failwith ("Presburger.b_apply_one_term: attempting to substitute arithmetic term for boolean var")
                else
                  pf
              | BConst _ -> pf
              | XPure _ -> pf (* WN XPure : not possible *)
              | BVar (bv, pos) ->
                begin try
                    let _, e = List.find (fun (fr,_) -> eq_spec_var bv fr) sst in
                    let v = get_var_opt e in
                    match v with
                    | Some v -> BVar (v, pos)
                    | None -> failwith ("Presburger.b_apply_one_term: attempting to substitute arithmetic term for boolean var")
                  with Not_found -> pf end
              | Lt (a1, a2, pos) -> Lt (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | Lte (a1, a2, pos) -> Lte (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | Gt (a1, a2, pos) -> Gt (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | SubAnn (a1, a2, pos) -> SubAnn (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | Gte (a1, a2, pos) -> Gte (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | Eq (a1, a2, pos) -> Eq (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | Neq (a1, a2, pos) -> Neq (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | EqMax (a1, a2, a3, pos) -> EqMax (a_apply_par_term sst a1, a_apply_par_term sst a2, a_apply_par_term sst a3, pos)
              | EqMin (a1, a2, a3, pos) -> EqMin (a_apply_par_term sst a1, a_apply_par_term sst a2, a_apply_par_term sst a3, pos)
              | BagIn (v, a1, pos) -> BagIn (v, a_apply_par_term sst a1, pos)
              | BagNotIn (v, a1, pos) -> BagNotIn (v, a_apply_par_term sst a1, pos)
              | BagSub (a1, a2, pos) -> BagSub (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | BagMax (v1, v2, pos) -> BagMax (v1, v2, pos)
              | BagMin (v1, v2, pos) -> BagMin (v1, v2, pos)
              (* | VarPerm (ct,ls,pos) -> VarPerm (ct,ls,pos) (*Do not substitute*) *)
              | ListIn (a1, a2, pos) -> ListIn (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | ListNotIn (a1, a2, pos) -> ListNotIn (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | ListAllN (a1, a2, pos) -> ListAllN (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | ListPerm (a1, a2, pos) -> ListPerm (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
              | RelForm (r, args, pos) -> RelForm (r, a_apply_par_term_list sst args, pos) (* An Hoa *)
              | ImmRel (r, cond, pos) -> ImmRel (helper r, cond, pos)
              | LexVar t_info -> 
                LexVar { t_info with 
                         lex_ann = map_term_ann (apply_par_term sst) (a_apply_par_term sst) t_info.lex_ann; 
                         lex_exp = a_apply_par_term_list sst t_info.lex_exp;
                         lex_tmp = a_apply_par_term_list sst t_info.lex_tmp; } 
    in helper pf
  in (npf,il)

and subs_one_term sst v orig = List.fold_left (fun old  -> fun  (fr,t) -> if (eq_spec_var fr v) then t else old) orig sst 

and a_apply_par_term (sst : (spec_var * exp) list) e =
  match e with
  | Null _ 
  | IConst _ 
  | InfConst _
  | NegInfConst _
  | FConst _ 
  | AConst _ 
  | Bptriple _ (*TOCHECK*)
  | Tsconst _ -> e
  | Tup2 ((a1,a2),pos) -> Tup2 ((a_apply_par_term sst a1,a_apply_par_term sst a2),pos)
  | Add (a1, a2, pos) -> normalize_add (Add (a_apply_par_term sst a1, a_apply_par_term sst a2, pos))
  | Subtract (a1, a2, pos) -> Subtract (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | Mult (a1, a2, pos) -> Mult (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | Div (a1, a2, pos) -> Div (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | Var (sv, pos) -> subs_one_term sst sv e (* if eq_spec_var sv fr then t else e *)
  | Level (sv, pos) -> subs_one_term sst sv e
  | Max (a1, a2, pos) -> Max (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | Min (a1, a2, pos) -> Min (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | TypeCast (ty, a, pos) -> TypeCast (ty, a_apply_par_term sst a, pos)
  | Bag (alist, pos) -> Bag ((a_apply_par_term_list sst alist), pos)
  | BagUnion (alist, pos) -> BagUnion ((a_apply_par_term_list sst alist), pos)
  | BagIntersect (alist, pos) -> BagIntersect ((a_apply_par_term_list sst alist), pos)
  | BagDiff (a1, a2, pos) -> BagDiff (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | List (alist, pos) -> List ((a_apply_par_term_list sst alist), pos)
  | ListAppend (alist, pos) -> ListAppend ((a_apply_par_term_list sst alist), pos)
  | ListCons (a1, a2, pos) -> ListCons (a_apply_par_term sst a1, a_apply_par_term sst a2, pos)
  | ListHead (a1, pos) -> ListHead (a_apply_par_term sst a1, pos)
  | ListTail (a1, pos) -> ListTail (a_apply_par_term sst a1, pos)
  | ListLength (a1, pos) -> ListLength (a_apply_par_term sst a1, pos)
  | ListReverse (a1, pos) -> ListReverse (a_apply_par_term sst a1, pos)
  | Func (a, i, pos) ->
    let a1 = subs_one_term sst a (Var (a,pos)) in
    (match a1 with
     | Var (a2,_) -> Func (a2, a_apply_par_term_list sst i, pos) 
     | _ -> failwith "Cannot substitute a function by a non variable!\n")  
  | ArrayAt (a, i, pos) -> (* An Hoa : CHECK BUG DETECTED - substitute a as well *)
    let a1 = subs_one_term sst a (Var (a,pos)) in
    (match a1 with
     | Var (a2,_) -> ArrayAt (a2, a_apply_par_term_list sst i, pos) 
     | _ -> failwith "Cannot substitute an array variable by a non variable!\n") 
  | Template t -> Template { t with 
                             templ_args = List.map (a_apply_par_term sst) t.templ_args;
                             templ_body = map_opt (a_apply_par_term sst) t.templ_body; }

and a_apply_par_term_list sst alist = match alist with
  |[] -> []
  |a :: rest -> (a_apply_par_term sst a) :: (a_apply_par_term_list sst rest)

and apply_one_term (fr, t) f = match f with
  | BForm (bf,lbl) -> BForm (b_apply_one_term (fr, t) bf , lbl)
  | And (p1, p2, pos) -> And (apply_one_term (fr, t) p1, apply_one_term (fr, t) p2, pos)
  | Or (p1, p2, lbl, pos) -> Or (apply_one_term (fr, t) p1, apply_one_term (fr, t) p2, lbl, pos)
  | Not (p, lbl, pos) -> Not (apply_one_term (fr, t) p, lbl, pos)
  | Forall (v, qf, lbl, pos) -> if eq_spec_var v fr then f else Forall (v, apply_one_term (fr, t) qf, lbl, pos)
  | Exists (v, qf, lbl, pos) -> if eq_spec_var v fr then f else Exists (v, apply_one_term (fr, t) qf, lbl, pos)
  | AndList b -> AndList (map_l_snd (apply_one_term (fr,t)) b)

and b_apply_one_term ((fr, t) : (spec_var * exp)) bf =
  let (pf,il) = bf in
  let npf = let rec helper pf =
              match pf with
              | Frm (fv, pos) -> if eq_spec_var fv fr then
                  match t with
                  | Var (t,_) -> Frm (t,pos)
                  | _ -> failwith ("Presburger.b_apply_one_term: attempting to substitute arithmetic term for boolean var")
                else
                  pf
              | BConst _ -> pf
              | XPure _ -> pf
              | BVar (bv, pos) ->
                if eq_spec_var bv fr then
                  match t with 
                  | Var (t,_) -> BVar (t,pos)
                  | _ -> failwith ("Presburger.b_apply_one_term: attempting to substitute arithmetic term for boolean var")
                else
                  pf
              | Lt (a1, a2, pos) -> Lt (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | Lte (a1, a2, pos) -> Lte (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | Gt (a1, a2, pos) -> Gt (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | Gte (a1, a2, pos) -> Gte (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | SubAnn (a1, a2, pos) -> SubAnn (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | Eq (a1, a2, pos) -> Eq (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | Neq (a1, a2, pos) -> Neq (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | EqMax (a1, a2, a3, pos) -> EqMax (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, a_apply_one_term (fr, t) a3, pos)
              | EqMin (a1, a2, a3, pos) -> EqMin (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, a_apply_one_term (fr, t) a3, pos)
              | BagIn (v, a1, pos) -> 
                let new_v = if eq_spec_var v fr then
                    match t with
                    | Var (tv,pos) -> tv
                    | _ ->
                      let () = print_endline_quiet "[Warning] b_apply_one_term: cannot replace a bag variable with an expression" in
                      v
                  else v
                in
                BagIn (new_v, a_apply_one_term (fr, t) a1, pos)(*what if v is a variable that need to be applied ??? MAY need to expect v to expression as well*)
              | BagNotIn (v, a1, pos) ->
                let new_v = if eq_spec_var v fr then
                    match t with
                    | Var (tv,pos) -> tv
                    | _ ->
                      let () = print_endline_quiet "[Warning] b_apply_one_term: cannot replace a bag variable with an expression" in
                      v
                  else v
                in
                BagNotIn (new_v, a_apply_one_term (fr, t) a1, pos)
              | BagSub (a1, a2, pos) -> BagSub (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | BagMax (v1, v2, pos) -> BagMax (v1, v2, pos)
              | BagMin (v1, v2, pos) -> BagMin (v1, v2, pos)
              (* | VarPerm (ct,ls,pos) -> VarPerm (ct,ls,pos) (* Do not substitute, is is the list of variable names*) *)
              | ListIn (a1, a2, pos) -> ListIn (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | ListNotIn (a1, a2, pos) -> ListNotIn (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | ListAllN (a1, a2, pos) -> ListAllN (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | ListPerm (a1, a2, pos) -> ListPerm (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
              | RelForm (r, args, pos) -> RelForm (r, List.map (a_apply_one_term (fr, t)) args, pos) (* An Hoa *)
              | ImmRel (r, cond, pos) -> ImmRel (helper r, cond, pos)
              | LexVar t_info -> 
                LexVar { t_info with
                         lex_ann = map_term_ann (apply_one_term (fr, t)) (a_apply_one_term (fr, t)) t_info.lex_ann;
                         lex_exp = List.map (a_apply_one_term (fr, t)) t_info.lex_exp; 
                         lex_tmp = List.map (a_apply_one_term (fr, t)) t_info.lex_tmp; } 
    in helper pf
  in (npf,il)

and a_apply_one_term ((fr, t) : (spec_var * exp)) e = match e with
  | Null _ 
  | IConst _ 
  | AConst _ 
  | InfConst _ 
  | NegInfConst _ 
  | FConst _ 
  | Bptriple _ -> e
  | Tsconst _ -> e
  | Tup2 ((a1,a2),pos) -> Tup2 ((a_apply_one_term (fr,t) a1,a_apply_one_term (fr,t) a2),pos)
  | Add (a1, a2, pos) -> normalize_add (Add (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos))
  | Subtract (a1, a2, pos) -> Subtract (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | Mult (a1, a2, pos) -> Mult (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | Div (a1, a2, pos) -> Div (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | Var (sv, pos) -> if eq_spec_var sv fr then t else e
  | Level (sv, pos) -> e (* if eq_spec_var sv fr then t else e *) (*donot replace locklevel by any expression*)
  | Max (a1, a2, pos) -> Max (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | Min (a1, a2, pos) -> Min (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | TypeCast (ty, a, pos) -> TypeCast (ty, a_apply_one_term (fr, t) a, pos)
  | Bag (alist, pos) -> Bag ((a_apply_one_term_list (fr, t) alist), pos)
  | BagUnion (alist, pos) -> BagUnion ((a_apply_one_term_list (fr, t) alist), pos)
  | BagIntersect (alist, pos) -> BagIntersect ((a_apply_one_term_list (fr, t) alist), pos)
  | BagDiff (a1, a2, pos) -> BagDiff (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | List (alist, pos) -> List ((a_apply_one_term_list (fr, t) alist), pos)
  | ListAppend (alist, pos) -> ListAppend ((a_apply_one_term_list (fr, t) alist), pos)
  | ListCons (a1, a2, pos) -> ListCons (a_apply_one_term (fr, t) a1, a_apply_one_term (fr, t) a2, pos)
  | ListHead (a1, pos) -> ListHead (a_apply_one_term (fr, t) a1, pos)
  | ListTail (a1, pos) -> ListTail (a_apply_one_term (fr, t) a1, pos)
  | ListLength (a1, pos) -> ListLength (a_apply_one_term (fr, t) a1, pos)
  | ListReverse (a1, pos) -> ListReverse (a_apply_one_term (fr, t) a1, pos)
  | Func (a, i, pos) ->
    let a1 = if eq_spec_var a fr then 
        (match t with
         | Var (a2, _) -> a2
         | _ -> failwith "Cannot apply a non-variable term to a function.")
      else a in
    Func (a1, a_apply_one_term_list (fr, t) i, pos)
  | ArrayAt (a, i, pos) -> 
    let a1 = if eq_spec_var a fr then 
        (match t with
         | Var (a2, _) -> a2
         | _ -> failwith "Cannot apply a non-variable term to an array variable.")
      else a in
    ArrayAt (a1, a_apply_one_term_list (fr, t) i, pos) (* An Hoa *)
  | Template tp -> Template { tp with 
                              templ_args = List.map (a_apply_one_term (fr, t)) tp.templ_args; 
                              templ_body = map_opt (a_apply_one_term (fr, t)) tp.templ_body; }


and a_apply_one_term_selective variance ((fr, t) : (spec_var * exp)) e : (bool*exp) = 
  let rec a_apply_one_term_list crt_var alist = match alist with
    |[] -> (false,[])
    |a :: rest -> 
      let b1,r1 = (helper crt_var a) in
      let b2,r2 = (a_apply_one_term_list crt_var rest) in
      ((b1||b2),(r1::r2))
  and helper crt_var e = match e with
    | Null _   
    | IConst _
    | InfConst _  
    | NegInfConst _  
    | FConst _ 
    | AConst _ 
    | Tsconst _ -> (false,e)
    | Bptriple _ -> (false,e) (* TOCHECK *)
    | Tup2 ((a1,a2),pos) ->
      let b1, r1 = helper crt_var a1 in
      let b2, r2 = helper crt_var a2 in
      ((b1||b2), Tup2 ((r1, r2), pos))
    | Add (a1, a2, pos) -> 
      let b1, r1 = helper crt_var a1 in
      let b2, r2 = helper crt_var a2 in
      ((b1||b2), Add (r1, r2, pos))
    | Subtract (a1, a2, pos) -> 
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper (not crt_var) a2 in
      (b1||b2, Subtract (r1 , r2 , pos))
    | Mult (a1, a2, pos) ->
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper crt_var a2 in
      (b1||b2, Mult (r1 , r2 , pos))
    | Div (a1, a2, pos) ->
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper (not crt_var) a2 in
      (b1||b2, Div (r1 , r2 , pos))
    | Var (sv, pos) -> if ((variance==crt_var)||(eq_spec_var sv fr)) then (true, t) else (false, e)
    | Level (sv, pos) -> if ((variance==crt_var)||(eq_spec_var sv fr)) then (true, t) else (false, e)
    | Max (a1, a2, pos) -> 
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper crt_var a2 in
      (b1||b2, Max (r1 , r2 , pos))
    | Min (a1, a2, pos) -> 
      let b1 , r1 = helper (not crt_var) a1 in
      let b2 , r2 = helper (not crt_var) a2 in
      (b1||b2, Min (r1 , r2 , pos))
    | TypeCast (ty, a, pos) ->
      let b, r = helper (not crt_var) a in
      (b, TypeCast (ty, r, pos))
    | Bag (alist, pos) -> 
      let b1,r1 = (a_apply_one_term_list crt_var alist) in
      (b1,Bag (r1, pos))
    | BagUnion (alist, pos) -> 
      let b1,r1 = (a_apply_one_term_list crt_var alist) in
      (b1,BagUnion (r1, pos))
    | BagIntersect (alist, pos) -> 
      let b1,r1 = (a_apply_one_term_list (not crt_var) (List.tl alist)) in
      let b2,r2 = helper crt_var (List.hd alist) in
      (b1||b2 ,BagIntersect (r2::r1, pos))
    | BagDiff (a1, a2, pos) -> 
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper (not crt_var) a2 in
      (b1||b2, BagDiff (r1 , r2 , pos))
    | List (alist, pos) -> 
      let b1,r1 = (a_apply_one_term_list crt_var alist) in
      (b1,List (r1, pos))
    | ListAppend (alist, pos) -> 
      let b1,r1 = (a_apply_one_term_list crt_var alist) in
      (b1,ListAppend (r1, pos))
    | ListCons (a1, a2, pos) -> 
      let b1 , r1 = helper crt_var a1 in
      let b2 , r2 = helper crt_var a2 in
      (b1||b2, ListCons (r1 , r2 , pos))
    | ListHead (a1, pos) -> 
      let b1,r1 = (helper crt_var a1) in
      (b1,ListHead (r1, pos))
    | ListTail (a1, pos) -> 
      let b1,r1 = (helper crt_var a1) in
      (b1,ListTail (r1, pos))
    | ListLength (a1, pos) -> 
      let b1,r1 = (helper crt_var a1) in
      (b1,ListLength (r1, pos))
    | ListReverse (a1, pos) -> 
      let b1,r1 = (helper crt_var a1) in
      (b1,ListReverse (r1, pos))
    | Func (a, i, pos) ->
      let b1,i1 = (a_apply_one_term_list crt_var i) in
      (b1,Func (a, i1, pos))
    | ArrayAt (a, i, pos) -> (* An Hoa CHECK THIS! *)
      let b1,i1 = (a_apply_one_term_list crt_var i) in
      (b1,ArrayAt (a, i1, pos)) 
    | Template t -> 
      let b1, args = a_apply_one_term_list crt_var t.templ_args in
      let b2, body = map_opt_def (false, None) (fun e ->
          let b, e = helper crt_var e in b, Some e) t.templ_body in 
      (b1||b2, Template { t with templ_args = args; templ_body = body; })
  in (helper true e)

and a_apply_one_term_list (fr, t) alist = match alist with
  |[] -> []
  |a :: rest -> (a_apply_one_term (fr, t) a) :: (a_apply_one_term_list (fr, t) rest)

and rename_top_level_bound_vars (f : formula) = match f with
  | Or (f1, f2, lbl, pos) ->
    let rf1 = rename_top_level_bound_vars f1 in
    let rf2 = rename_top_level_bound_vars f2 in
    let resform = mkOr rf1 rf2 lbl pos in
    resform
  | And (f1, f2, pos) ->
    let rf1 = rename_top_level_bound_vars f1 in
    let rf2 = rename_top_level_bound_vars f2 in
    let resform = mkAnd rf1 rf2 pos in
    resform
  | AndList b -> AndList (map_l_snd rename_top_level_bound_vars b)
  | Exists (qvar, qf, lbl, pos) ->
    let renamed_f = rename_top_level_bound_vars qf in
    let new_qvar = fresh_spec_var qvar in
    let rho = [(qvar, new_qvar)] in
    let new_qf = subst rho renamed_f in
    let res_form = Exists (new_qvar, new_qf,lbl,  pos) in
    res_form
  | Forall (qvar, qf, lbl, pos) ->
    let renamed_f = rename_top_level_bound_vars qf in
    let new_qvar = fresh_spec_var qvar in
    let rho = [(qvar, new_qvar)] in
    let new_qf = subst rho renamed_f in
    let res_form = Forall (new_qvar, new_qf, lbl, pos) in
    res_form
  | _ -> f

and split_ex_quantifiers (f0 : formula) : (spec_var list * formula) = match f0 with
  | Exists (qv, qf, lbl, pos) ->
    let qvars, new_f = split_ex_quantifiers qf in
    (qv :: qvars, new_f)
  | _ -> ([], f0)

and split_ex_quantifiers_ext (f0 : formula) : (spec_var list * formula) = match f0 with
  | Exists (qv, qf, lbl, pos) ->
    let qvars, new_f = split_ex_quantifiers qf in
    (qv :: qvars, new_f)
  | And (p1, p2, pos) -> let svl1 = fv p1 in
    let svl2 = fv p2 in
    let qvars1, new_f1 = split_ex_quantifiers_ext p1 in
    let qvars2, new_f2 = split_ex_quantifiers_ext p2 in
    if intersect_svl qvars1 svl2 = [] && intersect_svl qvars2 svl1 = [] then
      (qvars1@qvars2, mkAnd new_f1 new_f2 pos)
    else ([], f0)
  | _ -> ([], f0)

and add_quantifiers qvars f0=
  match qvars with
  | [] -> f0
  | v::rest ->  add_quantifiers rest (Exists (v, f0, None, pos_of_formula f0))

and split_forall_quantifiers (f0 : formula) = match f0 with
  | Forall (qv, qf, lbl, pos) ->
    let qvars, new_f,_,_ = split_forall_quantifiers qf in
    (qv :: qvars, new_f, lbl, pos)
  | _ -> ([], f0,None, no_pos)

(*
recursively idenfify existential variables
Assume name conflicts have been resolved (e.g.
exist v. exist v  does not exists)

Example:

 ex v1. v1=v2 & ex v3. v3=v4 -->
 (v1=v2&v3=v4), [v1,v3]
*)
and split_ex_quantifiers_rec_x (f0 : formula) : formula * (spec_var list) =
  let rec helper f0 = 
    match f0 with
    | BForm _ -> (f0,[])
    | And (f1, f2, pos) ->
      let n_f1,qvars1 = helper f1 in
      let n_f2,qvars2 = helper f2 in
      And (n_f1, n_f2, pos),qvars1@qvars2
    | AndList b -> 
      let nf,qvars = List.fold_left (fun (ls_f,vars) (_,f_b) -> 
          let nf,qvars = helper f_b in
          And (ls_f, nf, no_pos),vars@qvars
        ) ((mkTrue no_pos),[]) b in
      nf,qvars
    | Or (f1, f2, lbl, pos) ->
      let n_f1,qvars1 = helper f1 in
      let n_f2,qvars2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos),qvars1@qvars2
    | Not (f, lbl, pos) ->
      let n_f,qvars = helper f in
      Not (n_f, lbl, pos),qvars
    | Forall (sv, f, lbl, pos) ->
      let n_f,evars = helper f in
      Forall (sv, n_f, lbl, pos),evars
    | Exists (sv, f, lbl, pos) ->
      let n_f,evars = helper f in
      n_f, sv::evars
  in helper f0

and split_ex_quantifiers_rec (f0 : formula) : formula * (spec_var list) =
  let pr_out = pr_pair !print_formula !print_svl in
  Debug.no_1 "split_ex_quantifiers_rec"
    !print_formula pr_out
    split_ex_quantifiers_rec_x f0
(* More simplifications *)

(*
  EX quantifier elimination.

  EX x . x = T & P(x) ~-> P[T], T is term
  EX x . P[x] \/ Q[x] ~-> (EX x . P[x]) \/ (EX x . Q[x])
  EX x . P & Q[x] ~-> P & EX x. Q[x], x notin FV(P)

*)

(*
  List of bag variables.
*)
and bag_vars_formula (f0 : formula) : spec_var list = match f0 with
  | BForm (bf,lbl) -> (bag_vars_b_formula bf)
  | And (f1, f2, pos) -> (bag_vars_formula f1) @ (bag_vars_formula f2)
  | AndList b -> fold_l_snd bag_vars_formula b 
  | Or (f1, f2, lbl, pos)  -> (bag_vars_formula f1) @ (bag_vars_formula f2)
  | Not (f1, lbl, pos) -> (bag_vars_formula f1)
  | Forall (qvar, qf, lbl, pos) -> (bag_vars_formula qf)
  | Exists (qvar, qf, lbl, pos) -> (bag_vars_formula qf)

and bag_vars_b_formula (bf : b_formula) : spec_var list =
  let (pf,il) = bf in
  match pf with
  | BagIn (v1,_,_)
  | BagNotIn (v1,_,_) -> [v1]
  | BagMin (v1,v2,_)
  | BagMax (v1,v2,_) -> [v1;v2]
  | Eq (e1,e2,pos) ->
    let vars1 = bag_vars_exp e1 in
    let vars2 = bag_vars_exp e2 in
    (vars1@vars2)
  | _ -> []

and bag_vars_exp (e : exp) : spec_var list =
  let rec helper e =
    match e with
    | Bag (exps,pos) ->
      let vars = List.map ( fun e ->
          (match e with
           | Var (sv,pos) -> [sv]
           | Level (sv,pos) -> [sv]
           | _ -> [])
        ) exps in
      (List.concat vars)
    | BagUnion (exps,pos)
    | BagIntersect (exps,pos) ->
      let vars = List.map ( fun e ->
          let vars = helper e in
          vars
        ) exps in
      (List.concat vars)
    | BagDiff (e1,e2,pos) ->
      let vars1 = helper e1 in
      let vars2 = helper e2 in
      vars1@vars2
    | _ -> []
  in helper e

and  get_subst_equation_formula_vv (f0 : formula) (v : spec_var):((spec_var * spec_var) list * formula) = 
  let r1,r2 = get_subst_equation_formula f0 v true in
  let r =List.fold_left (fun a (c1,c2)->match c2 with
      | Var (v,_)-> (c1,v)::a
      | _ -> a ) [] r1 in
  (r,r2)

and get_subst_equation_formula (f0 : formula) (v : spec_var) only_vars: ((spec_var * exp) list * formula) =
  let pr_out = pr_pair (pr_list (pr_pair !print_sv !print_exp)) !print_formula in
  Debug.no_3 "get_subst_equation_formula"
    !print_formula !print_sv string_of_bool pr_out 
    get_subst_equation_formula_x f0 v only_vars

and get_subst_equation_formula_x (f0 : formula) (v : spec_var) only_vars: ((spec_var * exp) list * formula) =
  let bag_vars = bag_vars_formula f0 in
  (*OVERIDDING the input for soundness*)
  (*If there are bag constraints -> only find equations of variables
    such as x=v & x in BAG, but not x=v+1 & x in BAG*)
  let only_vars = if (Gen.BList.mem_eq eq_spec_var v bag_vars) then true else only_vars in
  let rec helper f0 v only_vars =
    match f0 with
    | And (f1, f2, pos) ->
      let st1, rf1 = helper f1 v only_vars in
      if not (Gen.is_empty st1) then
        (st1, mkAnd rf1 f2 pos)
      else
        let st2, rf2 = helper f2 v only_vars in
        (st2, mkAnd f1 rf2 pos)
    | AndList b -> 
      let r1,r2 = List.fold_left (fun (a1,b1) c-> 
          if Gen.is_empty a1 then 
            let a, b = helper (snd c) v only_vars in
            (a,b1@[(fst c, b)])
          else (a1, b1@[c]) 
        ) ([],[]) b in
      (r1, AndList r2)
    | BForm (bf,lbl) -> get_subst_equation_b_formula bf v lbl only_vars
    | _ -> ([], f0)
  in 
  let nondet_vars = collect_nondet_vars f0 in
  if Gen.BList.mem_eq eq_spec_var v nondet_vars then ([], f0)
  else helper f0 v only_vars

and get_subst_equation_b_formula_x (f : b_formula) (v : spec_var) lbl only_vars: ((spec_var * exp) list * formula) =
  let (pf,il) = f in
  match pf with
  | Eq (e1, e2, pos) -> begin
      match e1, e2 with
      | Var (sv1, _), Var (sv2, _) -> 
        if (eq_spec_var sv1 v) && (not (eq_spec_var sv2 v)) then ([(v, e2)], mkTrue no_pos )
        else if (eq_spec_var sv2 v) && (not (eq_spec_var sv1 v))  then ([(v, e1)], mkTrue no_pos )
        else ([], BForm (f,lbl))
      | Var (sv1, _), _  ->
        if only_vars then ([], BForm (f,lbl))
        else if (eq_spec_var sv1 v) &&(not (List.exists (fun sv -> eq_spec_var sv v) (afv e2))) then ([(v, e2)], mkTrue no_pos )
        else ([], BForm (f,lbl))
      | _ , Var (sv2, _) ->
        if only_vars then ([], BForm (f,lbl))
        else if (eq_spec_var sv2 v) && (not (List.exists (fun sv -> eq_spec_var sv v) (afv e1))) then ([(v, e1)], mkTrue no_pos )
        else ([], BForm (f,lbl))
      | Tsconst (t,_), Add (Var (sv,_),Tsconst (t1,_),_) 
      | Tsconst (t,_), Add (Tsconst (t1,_), Var (sv,_),_) -> 
        if only_vars then ([],BForm(f,lbl))
        else if (eq_spec_var sv v) then 
          if (Tree_shares.Ts.contains t t1) then ([(v,Tsconst (Tree_shares.Ts.subtract t t1, no_pos))],mkTrue no_pos)
          else ([],mkFalse no_pos)
        else ([],BForm (f,lbl))
      | _ ->([], BForm (f,lbl))
    end
  | _ -> ([], BForm (f,lbl))

and get_subst_equation_b_formula (f : b_formula) (v : spec_var) lbl only_vars: ((spec_var * exp) list * formula) =
  let pr_out = pr_pair (pr_list (pr_pair !print_sv !print_exp)) !print_formula in
  Debug.no_3 "get_subst_equation_b_formula "
    !print_b_formula !print_sv string_of_bool pr_out
    (fun _ _ _ -> get_subst_equation_b_formula_x f v lbl only_vars) f v only_vars


and get_all_vv_eqs (f0 : formula) : ((spec_var * spec_var) list * formula) =
  let pr = !print_formula in
  let pr_sv = !print_sv in
  let prr = pr_pair (pr_list (pr_pair pr_sv pr_sv)) pr in
  Debug.no_1 "get_all_vv_eqs" pr prr get_all_vv_eqs_x f0

and get_all_vv_eqs_x (f0 : formula) : ((spec_var * spec_var) list * formula) =  
  let rec helper f0 =  match f0 with
    | And (f1, f2, pos) ->
      let st1, rf1 = helper f1  in
      let st2, rf2 = helper f2  in
      (st1@st2, mkAnd rf1 rf2 pos)
    (* if not (Gen.is_empty st1) then *)
    (*   (st1, mkAnd rf1 f2 pos) *)
    (* else *)
    (*   (st2, mkAnd f1 rf2 pos) *)
    | AndList b -> 
      let r1,r2 = List.fold_left (fun (a1,b1) c-> 
          if Gen.is_empty a1 then 
            let a, b = helper (snd c) in
            (a,b1@[(fst c, b)])
          else (a1, b1@[c]) 
        ) ([],[]) b in
      (r1, AndList r2)
    | BForm (((Eq (Var (sv1, _), Var (sv2, _), pos)),_),_) -> ([(sv1, sv2)], mkTrue no_pos )	  
    | _ -> ([], f0)
  in helper f0

and get_all_vv_eqs_bform b = match b with
  | ((Eq (Var (sv1, _), Var (sv2, _), pos)),_) -> [(sv1, sv2)]
  | _ -> []

and perm_bounds (e:exp) : bool = match e with
  | Add (e1,e2,_) -> 
    (match e1 with 
     | Tsconst(f,_)-> Tree_shares.Ts.full f 
     | Var(v,_)-> full_perm_var_name = name_of_spec_var v
     |_-> false)||
    (match e2 with 
     | Tsconst(f,_)-> Tree_shares.Ts.full f 
     | Var(v,_)-> full_perm_var_name = name_of_spec_var v
     |_-> false)
  | _ -> false

and prune_perm_bounds f = 
  let helper (f,p) = match f with 
    | Eq (e1,e2,l) -> if !perm=Dperm && (perm_bounds e1 || perm_bounds e2) then  BConst (false, l),p else (f,p)
    | _ -> (f,p) in

  let rec helper_f f = match f with
    | BForm (b,l)-> BForm (helper b, l)
    | And (f1,f2,l) -> mkAnd (helper_f f1) (helper_f f2) l
    | AndList b -> AndList (map_l_snd helper_f b)
    | Or (f1,f2,l,pos) -> mkOr (helper_f f1) (helper_f f2) l pos
    | Not (f,l,pos) -> mkNot (helper_f f) l pos
    | Forall (v,f,l,pos) -> mkForall [v] (helper_f f) l pos
    | Exists (v,f,l,pos) -> mkExists [v] (helper_f f) l pos
  in
  helper_f f

(******************)
(*collect all bformula of f0*)
and list_of_bformula (f0:formula): formula list = match f0 with
  | BForm _
  | Forall _
  | Exists _ -> [f0]
  | And (f1,f2,_)
  | Or (f1,f2,_,_) ->(list_of_bformula f1)@(list_of_bformula f2)
  | Not (f1,_,_) ->list_of_bformula f1
  | AndList b -> fold_l_snd list_of_bformula b

and  check_dependent f ls_working: bool=
  let ls_var = fv f in
  let ls_varset = List.flatten (List.map fv ls_working) in
  let rec helper_check ls_lvarset =
    match ls_lvarset with
    | [] -> false
    | v::vs ->
      begin
        if List.mem v ls_var then
          true
        else
          helper_check vs
      end
  in
  helper_check ls_varset

and list_of_irr_bformula (ls_lhs:formula list) ls_working: ((formula list)*(formula list))=
  let rec helper_loop ls_llhs ls_lworking ls_lhs_rem =
    match ls_llhs with
    | [] ->  [], ls_lworking, ls_lhs_rem
    | f ::fs ->
      begin
              (*
                for each f2 in ls_lhs do
                if  depent(f2,f) then 
                - remove f2 out of ls_lhs;
                - add f2 into ls_working
              *)
        match (check_dependent f ls_working) with
        | true -> helper_loop fs (ls_lworking @ [f]) ls_lhs_rem
        | false -> helper_loop fs ls_lworking (ls_lhs_rem @ [f])
      end
  in
  let new_ls_lhs,new_ls_working, new_ls_lhs_rem = helper_loop ls_lhs [] [] in
  if ((List.length new_ls_lhs_rem) = (List.length ls_lhs)) then
    (*fixpoint*)
    ls_lhs,ls_working
  else
    list_of_irr_bformula new_ls_lhs_rem new_ls_working


(* ls denotes list of true predicate to be eliminated from f0*)
and elim_of_bformula (f0:formula) ls: formula  =  match f0 with
  | BForm f -> if List.mem f0 ls then BForm ((BConst (true,no_pos), None), snd f) else f0
  | And (f1,f2,p) -> mkAnd (elim_of_bformula f1 ls ) (elim_of_bformula f2 ls) p 
  | Or (f1,f2,l,p) -> mkOr (elim_of_bformula f1 ls ) (elim_of_bformula f2 ls) l p
  | Not (f1,l,p) -> mkNot (elim_of_bformula f1 ls) l p
  | Forall _ -> f0 (*should be improved*)
  | Exists _ -> f0 (*should be improved*)
  | AndList b -> AndList (map_l_snd (fun c-> elim_of_bformula c ls) b)

and string_of_ls_pure_formula ls =
  match ls with
  | [] -> ""
  | f::[] ->  (!print_formula f)
  | f::fs -> (!print_formula f) ^ "\n" ^ (string_of_ls_pure_formula fs)

and filter_redundant ante cons =
  Debug.no_2 "filter_redundant" !print_formula !print_formula !print_formula
    (fun a c -> filter_redundant_x a c) ante cons

and filter_redundant_x ante cons =
  let ls_ante = list_of_bformula ante in
  (* let () = print_endline ("ls_ante:" ^ (string_of_ls_pure_formula ls_ante)) in*)
  let ls_cons = list_of_bformula cons in
  (*  let () = print_endline ("ls_cons:" ^ (string_of_ls_pure_formula ls_cons)) in *)
  let ls_irr,_= list_of_irr_bformula ls_ante ls_cons in
  if ls_irr!=[] then x_dinfo_pp "Filtered some irrelevant b_formulas" no_pos else () ;
  (* let () = print_endline ("ls_irr:" ^ (string_of_ls_pure_formula ls_irr)) in*)
  let new_ante = elim_of_bformula ante ls_irr in
  (* let () = print_endline ("new_ante:" ^ (!print_formula new_ante)) in *)
  new_ante

and no_of_disjs (f0 : formula) : int =
  let rec helper f no = match f with
    | Or (f1, f2,_,_) ->
      let tmp1 = helper f2 no in
      let tmp2 = helper f1 tmp1 in
      tmp2
    | _ -> 1+no
  in
  helper f0 0

and find_bound v f0 =
  match f0 with
  | And (f1, f2, pos) ->
    begin
      let min1, max1 = find_bound v f1 in
      let min2, max2 = find_bound v f2 in
      let min = 
        match min1, min2 with
        | None, None -> None
        | Some m1, Some m2 -> if m1 < m2 then min1 else min2 
        | Some m, None -> min1
        | None, Some m -> min2
      in
      let max =
        match max1, max2 with
        | None, None -> None
        | Some m1, Some m2 -> if m1 > m2 then max1 else max2 
        | Some m, None -> max1 
        | None, Some m -> max2
      in
      (min, max)
    end
  | BForm (bf,_) -> find_bound_b_formula v bf
  | _ -> None, None

(* and find_bound_b_formula_redlog v f0 = *)
(* let cmd = "rlopt({" ^ (Redlog.rl_of_b_formula f0) ^ "}, " ^ (Redlog.rl_of_spec_var v) ^ ");\n" in *)
(* let res = Redlog.send_and_receive cmd in *)
(* print_endline res *)

and find_bound_b_formula v f0 =
  let val_for_max e included =
    if included then
      (* x <= e --> max(x) = floor(e) *)
      to_int_const e Floor
    else
      (* x < e --> max(x) = ceil(e) - 1 *)
      (to_int_const e Ceil) - 1
  in
  let val_for_min e included = 
    if included then
      (* x >= e --> min(x) = ceil(e) *)
      to_int_const e Ceil
    else
      (* x > e --> min(x) = floor(e) + 1 *)
      (to_int_const e Floor) + 1
  in
  let helper e1 e2 is_lt is_eq =
    if (is_var e1) && (is_num e2) then
      let v1 = to_var e1 in
      if eq_spec_var v1 v then
        if is_lt then
          let max = val_for_max e2 is_eq in
          (None, Some max)
        else
          let min = val_for_min e2 is_eq in
          (Some min, None)
      else
        (None, None)
    else if (is_var e2) && (is_num e1) then
      let v2 = to_var e2 in
      if eq_spec_var v2 v then
        if is_lt then
          let min = val_for_min e1 is_eq in
          (Some min, None)
        else
          let max = val_for_max e1 is_eq in
          (None, Some max)
      else
        (None, None)
    else
      (None, None)
  in
  let (pf,_) = f0 in
  match pf with
  | Lt (e1, e2, pos) -> helper e1 e2 true false
  | Lte (e1, e2, pos) -> helper e1 e2 true true
  | Gt (e1, e2, pos) -> helper e1 e2 false false
  | Gte (e1, e2, pos) -> helper e1 e2 false true
  | SubAnn (e1, e2, pos) -> helper e1 e2 true true
  | _ -> (None, None)

(* eliminate exists with the help of c1<=v<=c2 *)
and elim_exists_with_ineq (f0: formula): formula =
  match f0 with
  | Exists (qvar, qf,lbl, pos) ->
    begin
      match qf with
      | Or (qf1, qf2,lbl2, qpos) ->
        let new_qf1 = mkExists [qvar] qf1 lbl qpos in
        let new_qf2 = mkExists [qvar] qf2 lbl qpos in
        let eqf1 = elim_exists_with_ineq new_qf1 in
        let eqf2 = elim_exists_with_ineq new_qf2 in
        let res = mkOr eqf1 eqf2 lbl2 pos in
        res
      | _ ->
        let eqqf = elim_exists qf in
        let min, max = find_bound qvar eqqf in
        begin
          match min, max with
          | Some mi, Some ma -> 
            let res = ref (mkFalse pos) in
            begin
              for i = mi to ma do
                res := mkOr !res (apply_one_term (qvar, IConst (i, pos)) eqqf) lbl pos
              done;
              !res
            end
          | _ -> f0
        end
    end
  | And (f1, f2, pos) ->
    let ef1 = elim_exists_with_ineq f1 in
    let ef2 = elim_exists_with_ineq f2 in
    mkAnd ef1 ef2 pos
  | Or (f1, f2, lbl, pos) ->
    let ef1 = elim_exists_with_ineq f1 in
    let ef2 = elim_exists_with_ineq f2 in
    mkOr ef1 ef2 lbl pos
  | Not (f1, lbl, pos) ->
    let ef1 = elim_exists_with_ineq f1 in
    mkNot ef1 lbl pos
  | Forall (qvar, qf, lbl, pos) ->
    let eqf = elim_exists_with_ineq qf in
    mkForall [qvar] eqf lbl pos
  | BForm _ -> f0
  | AndList b-> AndList (map_l_snd elim_exists_with_ineq b)

and elim_exists (f0 : formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "elim_exists" pr pr elim_exists_x f0

(* eliminate exists with the help of v=exp *)
and elim_exists_x (f0 : formula) : formula = 
  let rec helper qvars f0 =
    match f0 with
    | Exists (qvar, qf, lbl, pos) -> helper (qvar::qvars) qf
    | Or (qf1, qf2, lbl2, qpos) ->
          (* let new_qf1 = mkExists [qvar] qf1 lbl qpos in *)
          (* let new_qf2 = mkExists [qvar] qf2 lbl qpos in *)
          let eqf1 = helper qvars qf1 in
          let eqf2 = helper qvars qf2 in
          let res = mkOr eqf1 eqf2 lbl2 qpos in
          res
    | _ ->
          (* let qf = helper qf in *)
          (* let qvars0, bare_f = split_ex_quantifiers qf in *)
          let qvars0 = qvars in
          let pos=no_pos in
          let bare_f = f0 in
          (* let qvars = qvar :: qvars0 in *)
          let conjs = list_of_conjs bare_f in
          let no_qvars_list, with_qvars_list = List.partition
              (fun cj -> disjoint qvars (fv cj)) conjs in
          (* the part that does not contain the quantified var *)
          let no_qvars = conj_of_list no_qvars_list pos in
          let () = y_tinfo_hp (add_str "elim_exists:no_qvars" !print_formula) no_qvars in
          (* now eliminate the quantified variables from the part that contains it *)
          let with_qvars = conj_of_list with_qvars_list pos in
          let () = y_tinfo_hp (add_str "elim_exists:with_qvars" !print_formula) with_qvars in
          (* now eliminate the top existential variable. *)
          (* let qvar = List.hd qvars in *)
          let rec eq_subs qvars f =
            match qvars with
              | [] -> [],f
              | qv::qvars -> 
                    let (st1,pp1) = eq_subs qvars f in
                    let (st2,pp2) = get_subst_equation_formula pp1 qv false in
                    (st1@st2,pp2)
          in
          let st,pp1 = eq_subs qvars with_qvars in
          (* let st, pp1 = get_subst_equation_formula with_qvars qvar false in *)
          if not (Gen.is_empty st) then
            let new_qf = subst_term st pp1 in
            let new_qf = prune_perm_bounds new_qf in
            (* let new_qf = mkExists qvars0 new_qf no_lbl pos in *)
            let tmp3 = helper qvars0 new_qf in
            let tmp4 = mkAnd no_qvars tmp3 pos in
            tmp4
          else (* if qvar is not equated to any variables, try the next one *)
            let tmp1 = f0 (*helper qf*) in
            let tmp2 = mkExists(*_with_simpl simpl*) qvars tmp1 None (* lbl *) pos in
            tmp2
      in
    (* | And (f1, f2, pos) -> mkAnd ( helper qvars f1) ( helper qvars f2) pos  *)
    (* | AndList b -> AndList (map_l_snd helper b) *)
    (* | Or (f1, f2, lbl, pos) -> mkOr ( helper f1) ( helper f2) lbl pos  *)
    (* | Not (f1, lbl, pos) -> mkNot (helper f1) lbl pos  *)
    (* | Forall (qvar, qf, lbl, pos) -> mkForall [qvar] (helper qf) lbl pos  *)
    (* | BForm _ -> f0 in *)
  helper [] f0
  (* let rec helper f0 = *)
  (*   match f0 with *)
  (*   | Exists (qvar, qf, lbl, pos) -> begin *)
  (*       match qf with *)
  (*       | Or (qf1, qf2, lbl2, qpos) -> *)
  (*         let new_qf1 = mkExists [qvar] qf1 lbl qpos in *)
  (*         let new_qf2 = mkExists [qvar] qf2 lbl qpos in *)
  (*         let eqf1 = helper new_qf1 in *)
  (*         let eqf2 = helper new_qf2 in *)
  (*         let res = mkOr eqf1 eqf2 lbl2 pos in *)
  (*         res *)
  (*       | _ -> *)
  (*         let qf = helper qf in *)
  (*         let qvars0, bare_f = split_ex_quantifiers qf in *)
  (*         let qvars = qvar :: qvars0 in *)
  (*         let conjs = list_of_conjs bare_f in *)
  (*         let no_qvars_list, with_qvars_list = List.partition *)
  (*             (fun cj -> disjoint qvars (fv cj)) conjs in *)
  (*         (\* the part that does not contain the quantified var *\) *)
  (*         let no_qvars = conj_of_list no_qvars_list pos in *)
  (*         let () = y_tinfo_hp (add_str "elim_exists:no_qvars" !print_formula) no_qvars in *)
  (*         (\* now eliminate the quantified variables from the part that contains it *\) *)
  (*         let with_qvars = conj_of_list with_qvars_list pos in *)
  (*         let () = y_tinfo_hp (add_str "elim_exists:with_qvars" !print_formula) with_qvars in *)
  (*         (\* now eliminate the top existential variable. *\) *)
  (*         let st, pp1 = get_subst_equation_formula with_qvars qvar false in *)
  (*         if not (Gen.is_empty st) then *)
  (*           let new_qf = subst_term st pp1 in *)
  (*           let new_qf = prune_perm_bounds new_qf in *)
  (*           let new_qf = mkExists qvars0 new_qf lbl pos in *)
  (*           let tmp3 = helper new_qf in *)
  (*           let tmp4 = mkAnd no_qvars tmp3 pos in *)
  (*           tmp4 *)
  (*         else (\* if qvar is not equated to any variables, try the next one *\) *)
  (*           let tmp1 = qf (\*helper qf*\) in *)
  (*           let tmp2 = mkExists(\*_with_simpl simpl*\) [qvar] tmp1 lbl pos in *)
  (*           tmp2 *)
  (*     end *)
  (*   | And (f1, f2, pos) -> mkAnd ( helper f1) ( helper f2) pos  *)
  (*   | AndList b -> AndList (map_l_snd helper b) *)
  (*   | Or (f1, f2, lbl, pos) -> mkOr ( helper f1) ( helper f2) lbl pos  *)
  (*   | Not (f1, lbl, pos) -> mkNot (helper f1) lbl pos  *)
  (*   | Forall (qvar, qf, lbl, pos) -> mkForall [qvar] (helper qf) lbl pos  *)
  (*   | BForm _ -> f0 in *)
  (* helper f0 *)

let mkExists_with_simpl simpl (vs : spec_var list) (f : formula) lbl pos = 
  let r = elim_exists (mkExists vs f lbl pos) in
  if contains_exists r then
    let r = simpl r in
    if !perm=Dperm then dperm_subst_simpl r else r
  else r

let mkExists_with_simpl simpl (vs : spec_var list) (f : formula) lbl pos = 
  Debug.no_2 "mkExists_with_simpl" !print_svl !print_formula !print_formula 
    (fun vs f -> mkExists_with_simpl simpl vs f lbl pos) vs f

(*
and elim_exists (f0 : formula) : formula = 
  Debug.no_1 "[cpure]elim_exists" !print_formula !print_formula elim_exists_x f0
*)
(*
add_gte_0 inp1 : exists(b_113:exists(b_128:(b_128+2)<=b_113 & (9+b_113)<=n))
add_gte_0@144 EXIT out : exists(b_113:0<=b_113 & 
  exists(b_128:0<=b_128 & (b_128+2)<=b_113 & (9+b_113)<=n))
*)
(* exists x: f0 ->  exists x: x>=0 /\ f0*)
(* this pre-processing is needed for mona *)
(* prior to sending a formula for Omega to simplify *)
let add_gte0_for_mona (f0 : formula): (formula)=
  let mkGte_f spec_var lbl pos=
    let zero = IConst (0, pos) in
    BForm (((mkLte zero (Var (spec_var, no_pos)) pos), None), lbl) in
  let rec helper f0 =
    match f0 with
    | Exists (qvar, qf, lbl, pos) ->
      begin
        let qf = helper qf in
        if (type_of_spec_var qvar)==Int then
          let gtes = mkGte_f qvar lbl no_pos in
          let and_formulas = mkAnd gtes qf pos in
          mkExists [qvar] and_formulas lbl pos
        else
          mkExists [qvar] qf lbl pos
      end
    | And (f1, f2, pos) -> mkAnd (helper f1) (helper f2) pos 
    | AndList b -> AndList (map_l_snd helper b)
    | Or (f1, f2, lbl, pos) -> mkOr (helper f1) (helper f2) lbl pos 
    | Not (f1, lbl, pos) ->  mkNot (helper f1) lbl pos 
    | Forall (qvar, qf, lbl, pos) -> mkForall [qvar] (helper qf) lbl pos 
    | BForm _ -> f0 in
  helper f0

let add_gte0_for_mona (f0 : formula): (formula) =
  let pr = !print_formula in
  Debug.no_1 "add_gte0_for_mona" pr pr add_gte0_for_mona f0

let add_flow_interval (f0 : formula) s b : formula =
  let pos = pos_of_formula f0 in
  let var = Var (mk_typed_spec_var Int "flow",pos) in
  let f1 = And (f0, mkGteExp var (IConst (s,pos)) pos, pos) in
  let f2 = And (f1, mkLteExp var (IConst (b,pos)) pos, pos) in
  (* let bf1 = (pf1,None) in *)
  (* let bf2 = (pf2,None) in *)
  (* let f1 = BForm (bf1,None) in *)
  (* let f2 = BForm (bf2,None) in *)
  f2

let add_flow_interval (f0 : formula) s b : formula =
  let pr = !print_formula in
  Debug.no_1 "add_flow_interval" pr pr (fun _ -> add_flow_interval f0 s b) f0

let add_flow_var_pf (pf0 : p_formula) : p_formula =
  match pf0 with
  | RelForm (sv,el,pos) -> RelForm (sv,el@[Var(mk_typed_spec_var Int "flow",pos)],pos)
  | _ -> pf0

let add_flow_var_pf (pf0 : p_formula) : p_formula =
  let pr = !print_p_formula in
  Debug.no_1 "add_flow_var_pf" pr pr add_flow_var_pf pf0

let rec add_flow_var (f0 : formula) : formula =
  let fv = fv f0 in
  if List.mem (mk_typed_spec_var Int "flow") fv then f0
  else match f0 with
    | BForm ((pf,ann),lbl) -> BForm ((add_flow_var_pf pf,ann),lbl)
    | And (f1,f2,pos) -> And (add_flow_var f1, add_flow_var f2, pos)
    | AndList al -> AndList (List.map (fun (t,f) -> (t, add_flow_var f)) al)
    | Or (f1,f2,lbl,pos) -> Or (add_flow_var f1, add_flow_var f2, lbl, pos)
    | Not (f,lbl,pos) -> Not (add_flow_var f, lbl, pos)
    | Forall (sv,f,lbl,pos) -> Forall (sv, add_flow_var f, lbl, pos)
    | Exists (sv,f,lbl,pos) -> Exists (sv, add_flow_var f, lbl, pos)

let add_flow_var (f0 : formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "add_flow_var" pr pr add_flow_var f0

(* (\* pretty printing for types *\) *)
(* let rec string_of_typ = function  *)
(*   | t -> string_of_prim_type t  *)
(*   | Named ot -> if ((String.compare ot "") ==0) then "ptr" else ("Object:"^ot) *)
(*   | Array (et, _) -> (string_of_typ et) ^ "[]" (\* An Hoa *\) *)

let compare_prime v1 v2 =
  if v1==v2 then 0
  else if v1==Unprimed then -1
  else 1

let compare_ident v1 v2 = String.compare v1 v2

let compare_spec_var (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) ->
    let c = compare_ident v1 v2 in
    if c=0 then
      compare_prime p1 p2 
    else c

(* convert ptr to integer constraints *)
(* ([a,a,b]  --> a!=a & a!=b & a!=b & a>0 & a>0 & b>0 *)
let baga_conv ?(neq_flag=false) baga : formula =
  let choose hd pos =
    if neq_flag then mkNeqNull hd pos
    else mkGtVarInt hd 0 pos in
  let baga = (* Elt.conv_var *) baga in
  if (List.length baga = 0) then
    mkTrue no_pos
  else if (List.length baga = 1) then
    choose (List.hd baga) no_pos
  else
    let rec helper i j baga len =
      let f1 = mkNeqVar (List.nth baga i) (List.nth baga j) no_pos in
      if i = len - 2 && j = len - 1 then
        f1
      else if j = len - 1 then
        let f2 = helper (i + 1) (i + 2) baga len in
        mkAnd f1 f2 no_pos
      else
        let f2 = helper i (j + 1) baga len in
        mkAnd f1 f2 no_pos
    in
    let f1 = helper 0 1 baga (List.length baga) in
    let f2 = List.fold_left (fun f sv -> mkAnd f (choose sv no_pos) no_pos)
        (choose (List.hd baga) no_pos) (List.tl baga) in
    mkAnd f1 f2 no_pos

(* ([a,a,b]  --> a=1 & a=2 & b=3 *)
let baga_enum baga : formula =
  (* let baga = Elt.conv_var baga in *)
  match baga with
  | [] -> mkTrue no_pos
  | h::ts ->
    (* let i = ref 1 in *)
    let f,_= List.fold_left (fun (f,i) sv ->
        (* i := !i + 1; *)
        let i = i + 1 in
        (mkAnd f (mkEqVarInt sv (* !i *)i no_pos) no_pos, i)
      ) ((mkEqVarInt (List.hd baga) (* !i *)1 no_pos),1) (List.tl baga)
    in f

(*
   [a,b]
    ==> a>0 & b>0 & a!=b  
        
   
*)
module SV =
struct 
  type t = spec_var
  let zero = mk_zero
  (* "_" to denote null value *)
  let is_zero x = x==zero
  let eq = eq_spec_var
  let compare = compare_spec_var
  let string_of x = (* "X"^ *)(string_of_spec_var x)
  let subst sst x =
    try
      snd(List.find (fun (v1,_) -> eq_spec_var x v1) sst)
    with _ -> x
    (* (\* convert ptr to integer constraints *\) *)
    (* (\* ([a,a,b]  --> a!=a & a!=b & a!=b & a>0 & a>0 & b>0 *\) *)
    (* let baga_conv ?(neq_flag=false) baga : formula = *)
    (*   let choose hd pos = *)
  let get_pure ?(enum_flag=false) ?(neq_flag=false) (lst:t list) = 
    (* let () = y_winfo_pp ("TODO: get_pure"^x_loc) in *)
    if enum_flag then baga_enum lst
    else baga_conv ~neq_flag:neq_flag lst

  let get_interval x = None
  let conv_var x = x
  let from_var x = x
  (* let conv_var_pairs x = x *)
  (* let from_var_pairs x = x *)
  let mk_elem_from_sv x = x
  (* throws exception when duplicate detected during merge *)
  let norm_baga (state:formula) (b:t list) = 
    b
  let rec merge_baga b1 b2 =
    match b1,b2 with
    | [],b | b,[] -> b
    | x1::t1, x2::t2 ->
      let c = compare x1 x2 in
      if c<0 then x1::(merge_baga t1 b2)
      else if c>0 then x2::(merge_baga b1 t2)
      else failwith "detected false"
  let rec hull_baga b1 b2 =
    match b1,b2 with
    | [],b | b,[] -> []
    | x1::t1, x2::t2 ->
      let c = compare x1 x2 in
      if c<0 then hull_baga t1 b2
      else if c>0 then hull_baga b1 t2
      else x1::(hull_baga t1 t2)
  let rec is_eq_baga b1 b2 =
    match b1,b2 with
    | [],[] -> true
    | x1::t1, x2::t2 ->
      let c = compare x1 x2 in
      if c=0 then is_eq_baga t1 t2
      else false
    |_,_ -> false
end;;

let mk_bform pf = BForm((pf,None),None) 

let mk_geq v i = 
  let lhs = mkVar v no_pos in
  let e = Gte(lhs,(mkIConst i no_pos),no_pos) in
  mk_bform e

let mk_exp_var v = 
  (* let lhs = mkVar v no_pos in *)
  let e = mkVar v no_pos in
  e

let get_exp_var e =
  match e with
    | Var(v,_) -> Some v
    | _ -> None

let mk_exp_geq lhs i = 
  (* let lhs = mkVar v no_pos in *)
  let e = Gte(lhs,(mkIConst i no_pos),no_pos) in
  mk_bform e

let mk_exp_leq lhs i = 
  (* let lhs = mkVar v no_pos in *)
  let e = Lte(lhs,(mkIConst i no_pos),no_pos) in
  mk_bform e

let mk_exp_neq_null lhs = 
  (* let lhs = mkVar v no_pos in *)
  let e = Neq(lhs,(Null no_pos),no_pos) in
  mk_bform e

(*
   [a,b,(e,base,offset)]
    ==> a>0 & b>0 & a!=b  
*)
(* to capture element as (sv, sv option) for both variable and interval *)
(*   (sv,None) denotes an address sv *)
(*   (sv1,Some(sv2)) denotes an interval sv1..(sv2-1) *)
(*   (sv1,Some(sv1)) is the same as empty *)
(* Alternative (sv1,Some(base,offset,intv)) sv1..(base+offset+intv-1) *)
(*   (base,Some(offset,len)) *)
(*  
      base,(offset,len)
      ptr = base+offset ..
      (self,2,0)
*)
module SV_INTV =
struct 
  type intv = (exp * exp) (* start and end+1 *)
  type t = spec_var * intv (* spec_var *) option
  let zero = (mk_zero,None)
  (* "_" to denote null value *)
  let is_zero x = x==zero
  (* need a stronger equality *)
  let eq (x1,m1) (x2,m2) =
    begin
      match m1,m2 with
      | None,None -> eq_spec_var x1 x2
      | Some(s1,n1),Some(s2,n2) -> failwith x_tbi
      | _,_ -> false
    end
  let compare (x1,m1) (x2,m2) = 
    begin
      match m1,m2 with
      | None,None -> compare_spec_var x1 x2
      | Some(s1,n1),Some(s2,n2) -> compare_spec_var x1 x2
      | None,Some _ -> -1
      | _, _ -> 1
    end
  let mk_addr x = (x,None)
  (* TODO : to change this function *)
  let get_interval (x,y) = 
   let () = y_tinfo_pp "inside get_interval (SV_INTV)" in
    match y with
    | None -> None
    | Some exp -> Some(x,exp)
                   (* Some(x,id) *)
  let string_of (sv,sv_opt) =
    (* let () = y_tinfo_pp "inside SV_INTV" in *)
    let pr = string_of_spec_var in
    let pr_e = !print_exp in
    match sv_opt with
    | None ->  pr sv
    | Some sv2 -> pr_pair pr (pr_pair pr_e pr_e) (sv,sv2)
  let subst sst (v,opt) =
    let repl_e (e1,e2) = (e_apply_subs sst e1,e_apply_subs sst e2) in
    let repl x =
      try
        snd(List.find (fun (v1,_) -> eq_spec_var x v1) sst)
      with _ -> x in
    (repl v,map_opt repl_e opt)
  (* [(b,d),(b2,d2)],p   ==> p & (d>0 -> b!=null) & (d2>0 -> b2!=null) *)
  (* [(b,d),(b2,d2)],p   ==> p & (d>0 -> b!=null) & (d2>0 -> b2!=null) & (d<=b2||d2<=b) (to ensure disjointness) *)
  let get_pure ?(enum_flag=false) ?(neq_flag=false) (lst:t list) =
    let gen_disj tlst =
      let gen_disj_f basenew eh et base e1 e2=
        (mkOr
           (mkNot (mkEqVar basenew base no_pos) None no_pos)
           (mkOr (BForm (((mkGte eh e2 no_pos),None),None)) (BForm (((mkGte e1 et no_pos),None),None)) None no_pos)
           None
           no_pos)
      in
      let rec helper ((base,(e1,e2)) as e) lst =
        match lst with
        | [] -> []
        | (basenew,(eh,et))::rest ->
           (gen_disj_f base e1 e2 basenew eh et)::(helper e rest)
      in
      let rec merge_and_list lst =
        match lst with
        | [] -> None
        | [h] -> Some h
        | h::rest ->
           (match (merge_and_list rest) with
            | Some r -> Some (mkAnd h r no_pos)
            | None -> Some h)
      in
      let rec proc tlst =
        match tlst with
        | [] -> []
        | h::rest -> (helper h rest)@(proc rest)
      in
      merge_and_list (proc tlst)
    in
    let () = y_tinfo_pp "inside get_pure (SV_INTV)" in
    (* let () = y_winfo_pp ("TODO: get_pure"^x_loc) in *)
    let lst_intv = List.fold_left (fun acc (base,s) -> match s with
        | None -> acc
        | Some(b,d) -> (base,(b,d))::acc) [] lst in
    let add_intv_formula f lst =
      List.fold_left (fun acc (base,(b,d)) ->
        let f1 = mk_exp_leq (mkAdd (mkVar base no_pos) d no_pos) 0 in
          let f2 = mk_exp_neq_null (mkAdd (mkVar base no_pos) b no_pos)  in
          (* let f1 = mk_exp_leq  d  0 in *)
          (* let f2 = mk_exp_neq_null b   in *)
        let f = mkOr f1 f2 None no_pos in
        mkAnd acc f no_pos
      ) f lst in
    let lst = List.filter (fun (_,p) -> p==None) lst in
    let lst = List.map fst lst in
    if enum_flag
    then
      let () = y_tinfo_pp "inside get_pure (SV_INTV), enum_flag is true" in
      let baga_enum_lst = baga_enum lst in
      let () = y_tinfo_hp (add_str "(baga_enum) lst:" !print_formula) baga_enum_lst in
      baga_enum_lst
    else
      let f = baga_conv ~neq_flag:neq_flag lst in
      (* (match gen_disj lst_intv with *)
      (*  | None -> mkTrue no_pos (\* add_intv_formula f lst_intv *\) *)
      (*  | Some disj_f -> *)
      (*     disj_f) *)
      (*     (\* mkAnd (add_intv_formula f lst_intv) disj_f no_pos) *\) *)
      (match gen_disj lst_intv with
       | None -> add_intv_formula f lst_intv
       | Some disj_f ->
          mkAnd (add_intv_formula f lst_intv) disj_f no_pos)
                   
  let conv_var lst = 
    let lst = List.filter (fun (_,o) -> o==None) lst in
    List.map fst lst
  let part_var lst = 
    List.partition (fun (_,o) -> o==None) lst
  let from_var lst = 
    List.map (fun v -> (v,None)) lst
  (* let conv_var_pairs lst =  *)
  (*   List.map (fun ((x1,_),(x2,_)) -> (x1,x2)) lst *)
  (* let from_var_pairs lst =  *)
  (*   List.map (fun (v1,v2) -> ((v1,None),(v2,None))) lst *)
  let mk_elem_from_sv x = (x,None)
  (* let mk_elem x = mk_elem_from_sv (x,None) *)
  (* throws exception when duplicate detected during merge *)
  let norm_baga (state:formula) (b:t list) = 
    let () = y_tinfo_pp x_tbi in
    b
  let rec merge_baga b1 b2 =
    match b1,b2 with
    | [],b | b,[] -> b
    | x1::t1, x2::t2 ->
      let c = compare_spec_var x1 x2 in
      if c<0 then x1::(merge_baga t1 b2)
      else if c>0 then x2::(merge_baga b1 t2)
      else failwith "detected false"

  let merge_baga (b1:t list) (b2:t list) : t list =
    let b1,r1 = part_var (* List.map fst *) b1 in
    let b2,r2 = part_var (* List.map fst *) b2 in
    let b3 = merge_baga (List.map fst b1) (List.map fst b2) in
    (List.map (fun v -> (v,None)) b3)@(r1@r2)

  let rec hull_baga b1 b2 =
    match b1,b2 with
    | [],b | b,[] -> []
    | x1::t1, x2::t2 ->
      let c = compare_spec_var x1 x2 in
      if c<0 then hull_baga t1 b2
      else if c>0 then hull_baga b1 t2
      else x1::(hull_baga t1 t2)

  let hull_baga (b1:t list) (b2:t list) : t list =
    let b1 = conv_var (* List.map fst *) b1 in
    let b2 = conv_var (* List.map fst *) b2 in
    let b3 = hull_baga b1 b2 in
    List.map (fun v -> (v,None)) b3

  let rec is_eq_baga b1 b2 =
    match b1,b2 with
    | [],[] -> true
    | x1::t1, x2::t2 ->
      let c = compare_spec_var x1 x2 in
      if c=0 then is_eq_baga t1 t2
      else false
    |_,_ -> false

  let is_eq_baga (b1:t list) (b2:t list) : bool =
    let () = y_tinfo_pp "is_eq_baga may be unsound" in
    let b1 = conv_var (* List.map fst *) b1 in
    let b2 = conv_var (* List.map fst *) b2 in
     let b3 = is_eq_baga b1 b2 in
    (* List.map (fun v -> (v,None)) *) b3

end;;

module Ptr =
  functor (Elt:Gen.EQ_TYPE) ->
  struct
    include Elt
    type tlist = t list
    type ef = t -> t -> bool
    module X = Gen.BListEQ(Elt)
    let sat x = true
    let overlap_eq eq = eq
    let intersect_eq eq (x:tlist)  (y:tlist) = Gen.BList.intersect_eq eq x y
    let overlap = eq
    let intersect (x:tlist)  (y:tlist) = X.intersect x y
    let star_union x y = x@y
  end;;

(* module CnjBag = *)
(*     functor (Elt:Gen.EQ_TYPE) -> *)
(* struct *)
(*   include Elt *)
(*   type tlist = (t list) list *)
(*   type ef = t -> t -> bool *)
(*   module X = Gen.BListEQ(Elt) *)
(*   let overlap_eq eq = eq *)
(*   let intersect_eq eq (x:tlist)  (y:tlist) = Gen.BList.intersect_eq eq x y *)
(*   let overlap = eq *)
(*   let intersect (x:tlist)  (y:tlist) = X.intersect x y *)
(*   let star_union x y = x@y *)
(* end;; *)

module PtrSV = Ptr(SV);;

module BagaSV = Gen.Baga(PtrSV);;
module EMapSV = Gen.EqMap(SV);;
module DisjSetSV = Gen.DisjSet(PtrSV);;
module SetSV = Set.Make(SV);;


(*added PtrSVINTV and DisjSetSVINTV for interval *)
module PtrSVINTV = Ptr(SV_INTV);;
module DisjSetSVINTV = Gen.DisjSet(PtrSVINTV);;

type baga_sv = BagaSV.baga

type var_aset = EMapSV.emap

(* TODO : this is an abstract type that should not be exposed *)

(* type ef_part = (spec_var list) list *)
(* type ef_pure = (spec_var list * (var_aset * ef_part) * (spec_var * spec_var) list) *)
(* (\* old extended pure formula *\) *)
(* (\* type ef_pure = (spec_var list * formula) *\) *)

(* (\* disjunctive extended pure formula *\) *)
(* (\* [] denotes false *\) *)
(* type ef_pure_disj = ef_pure list *)



(* need to remove constants and null *)
let fv_var_aset (e:var_aset) = EMapSV.get_elems e

let eq_spec_var_aset (aset: EMapSV.emap ) (sv1 : spec_var) (sv2 : spec_var) = match (sv1, sv2) with
  | (SpecVar (t1, v1, p1), SpecVar (t2, v2, p2)) -> EMapSV.is_equiv aset sv1 sv2

let eq_spec_var_aset (aset: EMapSV.emap ) (sv1 : spec_var) (sv2 : spec_var) =
  let pr = !print_sv in
  let pr1 = string_of_bool in
  Debug.no_2 "eq_spec_var_aset" pr pr pr1
    (fun _ _ -> eq_spec_var_aset aset sv1 sv2) sv1 sv2

let equalFormula_aset aset (f1:formula)(f2:formula):bool = equalFormula_f (eq_spec_var_aset aset)  f1 f2

and equalBFormula_aset aset  (f1:b_formula)(f2:b_formula) :bool = equalBFormula_f (eq_spec_var_aset aset)  f1 f2

and eqExp_aset aset  (f1:exp)(f2:exp):bool = eqExp_f (eq_spec_var_aset aset)  f1 f2


let rec eq_exp aset (e1 : exp) (e2 : exp) : bool = eqExp_aset aset e1 e2
(*
match (e1, e2) with
  | (Null(_), Null(_)) -> true
  | (Var(sv1, _), Var(sv2, _)) -> (eq_spec_var_aset aset sv1 sv2)
  | (IConst(i1, _), IConst(i2, _)) -> i1 = i2
  | (FConst(f1, _), FConst(f2, _)) -> f1 = f2
  | (Subtract(e11, e12, _), Subtract(e21, e22, _))
  | (Max(e11, e12, _), Max(e21, e22, _))
  | (Min(e11, e12, _), Min(e21, e22, _))
  | (Add(e11, e12, _), Add(e21, e22, _)) -> (eq_exp aset e11 e21) & (eq_exp aset e12 e22)
  | (Mult(e11, e12, _), Mult(e21, e22, _)) -> (eq_exp aset e11 e21) & (eq_exp aset e12 e22)
  | (Div(e11, e12, _), Div(e21, e22, _)) -> (eq_exp aset e11 e21) & (eq_exp aset e12 e22)
  | (Bag(e1, _), Bag(e2, _))
  | (BagUnion(e1, _), BagUnion(e2, _))
  | (BagIntersect(e1, _), BagIntersect(e2, _)) -> (eq_exp_list aset e1 e2)
  | (BagDiff(e1, e2, _), BagDiff(e3, e4, _)) -> (eq_exp aset e1 e3) & (eq_exp aset e2 e4)
  | (List (l1, _), List (l2, _))
  | (ListAppend (l1, _), ListAppend (l2, _)) -> if (List.length l1) = (List.length l2) then List.for_all2 (fun a b-> (eq_exp aset a b)) l1 l2 
    else false
  | (ListCons (e1, e2, _), ListCons (d1, d2, _)) -> (eq_exp aset e1 d1) && (eq_exp aset e2 d2)
  | (ListHead (e1, _), ListHead (e2, _))
  | (ListTail (e1, _), ListTail (e2, _))
  | (ListLength (e1, _), ListLength (e2, _))
  | (ListReverse (e1, _), ListReverse (e2, _)) -> (eq_exp aset e1 e2)
  | _ -> false


and eq_exp_list aset (e1 : exp list) (e2 : exp list) : bool =
  let rec eq_exp_list_helper (e1 : exp list) (e2 : exp list) = match e1 with
    | [] -> true
    | h :: t -> (List.exists (fun c -> eq_exp aset h c) e2) & (eq_exp_list_helper t e2)
  in
  (eq_exp_list_helper e1 e2) & (eq_exp_list_helper e2 e1)
*)

let eq_exp_no_aset (e1 : exp) (e2 : exp) : bool = eq_exp EMapSV.mkEmpty e1 e2        

let eq_b_formula aset (b1 : b_formula) (b2 : b_formula) : bool =  equalBFormula_aset aset b1 b2

let eq_b_formula_no_aset (b1 : b_formula) (b2 : b_formula) : bool = eq_b_formula EMapSV.mkEmpty b1 b2

let rec eq_pure_formula (f1 : formula) (f2 : formula) : bool = equalFormula f1 f2 


(**************************************************************)
(**************************************************************)
(**************************************************************)

(*
  Assumption filtering.

  Given entailment D1 => D2, we filter out "irrelevant" assumptions as follows.
  We convert D1 to a list of conjuncts (it is safe to drop conjunts from the LHS).
  The main heuristic is to keep only conjunts that mention "relevant" variables.
  Relevant variables may be only those on the RHS, and may or may not increase
  with new variables from newly added conjunts.

  (more and more aggressive filtering)
*)

(* This module cannot distinguish between primed and unprimed variables *)
module SVar = struct
  type t = spec_var
  let compare = fun sv1 -> fun sv2 -> (* compare_sv sv1 sv2 *)
    compare (name_of_spec_var sv1) (name_of_spec_var sv2)
end

(* This module can distinguish between primed and unprimed variables *)
module SVar_eq = struct
  type t = spec_var
  let compare = fun sv1 -> fun sv2 -> (* compare_sv sv1 sv2 *)
    compare (full_name_of_spec_var sv1) (full_name_of_spec_var sv2)
end

module SVarSet = Set.Make(SVar)

module SVarSet_eq = Set.Make(SVar_eq)

let set_of_list (ids : spec_var list) : SVarSet.t =
  List.fold_left (fun s -> fun i -> SVarSet.add i s) (SVarSet.empty) ids

let print_var_set vset =
  let tmp1 = SVarSet.elements vset in
  let tmp2 = List.map name_of_spec_var tmp1 in
  let tmp3 = String.concat ", " tmp2 in
  print_string ("\nvset:\n" ^ tmp3 ^ "\n")

let fv_wo_rel f =
  List.filter (fun v -> not(is_rel_var v)) (fv f)

(*
  filter from f0 conjuncts that mention variables related to rele_vars.
*)
(* Assumption: f0 is SAT *)
let rec filter_var (f0 : formula) (rele_vars0 : spec_var list) : formula =
  let is_relevant (fv, fvset) rele_var_set =
    not (SVarSet.is_empty (SVarSet.inter fvset rele_var_set)) in
  let rele_var_set = set_of_list rele_vars0 in
  let conjs = list_of_conjs f0 in
  let fv_list = List.map fv_wo_rel conjs in
  let fv_set = List.map set_of_list fv_list in
  let f_fv_list = List.combine conjs fv_set in
  let relevants0, unknowns0 = List.partition
      (fun f_fv -> is_relevant f_fv rele_var_set) f_fv_list in
  (* now select more "relevant" conjuncts *)
 (*
	   return value:
	   - relevants (formulas, fv_set) list
	   - unknowns
	   - updated relevant variable set
	*)
  let rele_var_set =
    let tmp1 = List.map snd relevants0 in
    let tmp2 = List.fold_left (fun s1 -> fun s2 -> SVarSet.union s1 s2) rele_var_set tmp1 in
    tmp2
  in
(*
	  let () = print_var_set rele_var_set in
	  let todo_unk = List.map
	  (fun ffv -> (print_string ("\nrelevants0: f\n" ^ (mona_of_formula (fst ffv)) ^ "\n")); print_var_set (snd ffv))
	  relevants0
	  in
*)
 (*
	  Perform a fixpoint to select all relevant formulas.
	*)
  let rec select_relevants relevants unknowns rele_var_set =
    let reles = ref relevants in
    let unks = ref unknowns in
    let unks_tmp = ref [] in
    let rvars = ref rele_var_set in
    let cont = ref true in
    while !cont do
      cont := false; (* assume we're done, unless the inner loop says otherwise *)
      let cont2 = ref true in
      while !cont2 do
        match !unks with
        | (unk :: rest) ->
          unks := rest;
      (*
					print_var_set !rvars;
					print_string ("\nunk:\n" ^ (mona_of_formula (fst unk)) ^ "\n");
				  *)
          if is_relevant unk !rvars then begin
            (* add variables from unk in as relevant vars *)
            cont := true;
            rvars := SVarSet.union (snd unk) !rvars;
            reles := unk :: !reles
     (*
					  print_string ("\nadding: " ^ (mona_of_formula (fst unk)) ^ "\n")
					*)
          end else
            unks_tmp := unk :: !unks_tmp
        | [] ->
          cont2 := false; (* terminate inner loop *)
          unks := !unks_tmp;
          unks_tmp := []
      done
    done;
    begin
      let rele_conjs = (* Gen.BList.remove_dups_eq equalFormula *) (List.map fst !reles) in
      let filtered_f = conj_of_list rele_conjs no_pos in
      let () = x_ninfo_hp (add_str "rele_conjs" (pr_list !print_formula)) rele_conjs no_pos in
      let () = x_ninfo_hp (add_str "filtered_f" (!print_formula)) filtered_f no_pos in
      (* WN : why this affected under_approx? *)
      if (is_False f0) && !Globals.filtering_false_flag then f0
      else filtered_f
    end
  in
  let filtered_f = select_relevants relevants0 unknowns0 rele_var_set in
  filtered_f


let filter_var (f0 : formula) (keep_slv : spec_var list) : formula =
  let pr1 = !print_formula in
  let pr2 = !print_svl in
  Debug.no_2 "filter_var" pr1 pr2 pr1
    (fun _ _ -> filter_var f0 keep_slv) f0 keep_slv

(* Assumption: f0 is SAT *)
(*implemented by L2 to replace the old one (the old one does not distinguish primed and unprimed)
  f is in CNF
  keep subformula which contains keep_slv and their relevant
*)
let filter_var_new_x (f : formula) (keep_slv : spec_var list) : formula =
  let rec get_new_rele_svl unk_fs old_keep_svl res_rele_fs res_unk_fs incr_keep=
    match unk_fs with
    | [] -> (res_rele_fs,res_unk_fs,old_keep_svl,incr_keep)
    | f::fs ->
      begin
        let () = x_ninfo_hp (add_str "svl: "  (!print_svl)) old_keep_svl no_pos in
        let () = x_ninfo_hp ( add_str "f: "   (!print_formula )) f no_pos in
        let svl = fv f in
        let () = x_ninfo_hp (add_str "svl f: "  !print_svl ) svl no_pos in
        let inters = intersect svl old_keep_svl in
        let () = x_ninfo_hp (add_str "inters: "  !print_svl)  inters no_pos in
        if inters = [] then
          get_new_rele_svl fs old_keep_svl res_rele_fs (res_unk_fs@[f]) incr_keep
        else
          begin
            let diff = Gen.BList.difference_eq eq_spec_var svl old_keep_svl in
            get_new_rele_svl fs (old_keep_svl@diff) (res_rele_fs@[f]) res_unk_fs (incr_keep@diff)
          end
      end
  in
  let rec filter_fix rele_fs unk_fs total_svl=
    let res_rele_fs,res_unk_fs,new_total_svl,incr_keep_svl = get_new_rele_svl unk_fs total_svl [] [] [] in
    if res_rele_fs = [] && incr_keep_svl = [] then
      (*reach fix point*)
      (rele_fs)
    else filter_fix (rele_fs@res_rele_fs) res_unk_fs new_total_svl
  in
  let conjs = list_of_conjs f in
  let keep_slv = remove_dups_svl keep_slv in
  (* let fv_list = List.map fv conjs in *)
  let rele_fs = filter_fix [] conjs keep_slv in
  conj_of_list rele_fs no_pos

let filter_var_new (f0 : formula) (keep_slv : spec_var list) : formula =
  let pr1 = !print_formula in
  let pr2 = !print_svl in
  Debug.no_2 "filter_var_new" pr1 pr2 pr1
    (fun _ _ -> filter_var_new_x f0 keep_slv) f0 keep_slv

(**************************************************************)
(**************************************************************)
(**************************************************************)

(*
  Break an entailment using the following rule:
  A -> B /\ C <=> (A -> B) /\ (A -> C)

  Return value: a list of new implications. The new antecedents
  are filtered. This works well in conjunction with existential
  quantifier elimintation and filtering.
*)

let rec break_implication (ante : formula) (conseq : formula) : ((formula * formula) list) =
  let conseqs = list_of_conjs conseq in
  let fvars = List.map fv conseqs in
  let antes = List.map (fun reles -> filter_var ante reles) fvars in
  let res = List.combine antes conseqs in
  res

(**************************************************************)
(**************************************************************)
(**************************************************************)
(*
	MOVED TO SOLVER.ML -> TO USE THE PRINTING METHODS

	We do a simplified translation towards CNF where we only take out the common
 	conjuncts from all the disjuncts:

	Ex:
 (a=1 & b=1) \/ (a=2 & b=2) - nothing common between the two disjuncts
 (a=1 & b=1 & c=3) \/ (a=2 & b=2 & c=3) ->  c=3 & ((a=1 & b=1) \/ (a=2 & b=2))

	let rec normalize_to_CNF (f : formula) pos : formula
 *)
(**************************************************************)
(**************************************************************)
(**************************************************************)

let find_rel_constraints_list lf desired =
  let lf_pair = List.map (fun c-> ((fv c),c)) lf in
  let var_list = fst (List.split lf_pair) in
  (*LDK: repeatedly collect vars that relate to desired vars*)
  let rec helper (fl:spec_var list) : spec_var list = 
    let nl = List.filter (fun c-> (Gen.BList.intersect_eq (eq_spec_var) c fl)!=[]) var_list in
    let nl = List.concat nl in
    let nl = Gen.BList.remove_dups_eq (eq_spec_var) (nl@fl) in
    if (List.length fl)=(List.length nl) then fl
    else helper nl in
  let fixp = helper desired in
  let pairs = List.filter (fun (c,_) -> (List.length (Gen.BList.intersect_eq (eq_spec_var) c fixp))>0) lf_pair in
  join_conjunctions (snd (List.split pairs))

(*find constraints in f that related to specvar in v_l*)  
let find_rel_constraints_x (f:formula) desired :formula = 
  if desired=[] then (mkTrue no_pos)
  else 
    let lf = split_conjunctions f in
    find_rel_constraints_list lf desired

let find_rel_constraints (f:formula) desired :formula = 
  Debug.no_2 "find_rel_constraints_x"
    !print_formula !print_svl !print_formula
    find_rel_constraints_x f desired


(*
  Drop bag and list constraints for satisfiability checking.
  Strict: drop bag vars as well
*)
let rec drop_bag_formula (f0 : formula) : formula = match f0 with
  | BForm (bf,lbl) -> BForm (drop_bag_b_formula bf, lbl)
  | And (f1, f2, pos) -> mkAnd (drop_bag_formula f1) (drop_bag_formula f2) pos 
  | AndList b -> AndList (map_l_snd drop_bag_formula b)
  | Or (f1, f2, lbl, pos) -> mkOr (drop_bag_formula f1) (drop_bag_formula f2) lbl pos 
  | Not (f1, lbl, pos) -> mkNot (drop_bag_formula f1) lbl pos
  | Forall (qvar, qf,lbl, pos) ->mkForall [qvar] (drop_bag_formula qf) lbl pos 
  | Exists (qvar, qf,lbl, pos) -> mkExists [qvar] ( drop_bag_formula qf) lbl pos 

and drop_bag_b_formula (bf : b_formula) : b_formula =
  let (pf,il) = bf in
  let npf = match pf with
    | BagIn _
    | BagNotIn _
    | BagSub _
    | BagMin _
    | BagMax _
    | ListIn _
    | ListNotIn _
    | ListAllN _
    | ListPerm _ -> BConst (true, no_pos)
    | Eq (e1, e2, pos)
    | Neq (e1, e2, pos) ->
      if (is_bag e1) || (is_bag e2) || (is_list e1) || (is_list e2) then
        BConst (true, pos)
      else
        pf
    | _ -> pf
  in (npf,il)

(*
  Drop floating-point constraints
*)
let rec drop_float_formula (f0 : formula) : formula = match f0 with
  | BForm (bf,lbl) -> BForm (drop_float_b_formula bf, lbl)
  | And (f1, f2, pos) -> mkAnd (drop_float_formula f1) (drop_float_formula f2) pos 
  | AndList b -> AndList (map_l_snd drop_float_formula b)
  | Or (f1, f2, lbl, pos) ->mkOr (drop_float_formula f1) (drop_float_formula f2) lbl pos 
  | Not (f1, lbl, pos) -> mkNot (drop_float_formula f1) lbl pos 
  | Forall (qvar, qf,lbl, pos) ->
    if (is_float_var qvar) then (drop_float_formula qf)
    else
      mkForall [qvar] (drop_float_formula qf) lbl pos 
  | Exists (qvar, qf,lbl, pos) ->
    if (is_float_var qvar) then (drop_float_formula qf)
    else
      mkExists [qvar] (drop_float_formula qf) lbl pos 

and drop_float_b_formula (bf : b_formula) : b_formula =
  if (is_float_bformula bf) then (BConst (true, no_pos),None)
  else bf

(*
  Drop VarPerm constraints for satisfiability checking.
*)
(* let rec drop_varperm_formula (f0 : formula) : formula = match f0 with                         *)
(*   | BForm (bf,lbl) -> BForm (drop_varperm_b_formula bf, lbl)                                  *)
(*   | And (f1, f2, pos) -> mkAnd (drop_varperm_formula f1) (drop_varperm_formula f2) pos        *)
(*   | AndList b -> AndList (map_l_snd drop_varperm_formula b)                                   *)
(*   | Or (f1, f2, lbl, pos) ->mkOr (drop_varperm_formula f1) (drop_varperm_formula f2) lbl pos  *)
(*   | Not (f1, lbl, pos) -> mkNot (drop_varperm_formula f1) lbl pos                             *)
(*   | Forall (qvar, qf,lbl, pos) -> mkForall [qvar] (drop_varperm_formula qf) lbl pos           *)
(*   | Exists (qvar, qf,lbl, pos) -> mkExists [qvar] (drop_varperm_formula qf) lbl pos           *)

(* and drop_varperm_b_formula (bf : b_formula) : b_formula =                                     *)
(*   let (pf,il) = bf in                                                                         *)
(*   let npf = match pf with                                                                     *)
(*     | VarPerm _ ->  BConst (true, no_pos)                                                     *)
(*     | _ -> pf                                                                                 *)
(*   in (npf,il)                                                                                 *)

(**************************************************************)
(**************************************************************)
(**************************************************************)

(*************************************************************************************************************************
   	05.06.2008:
   	Utilities for existential quantifier elimination:
   	- before we were only searching for substitutions of the form v1 = v2 and then substitute ex v1. P(v1) --> P(v2)
   	- now, we want to be more aggressive and search for substitutions of the form v1 = exp2; however, we can only apply these substitutions to the pure part
   	(due to the way shape predicates are recorded --> root pointer and args are suppose to be spec vars)
 *************************************************************************************************************************)

and apply_one_exp ((fr, t) : spec_var * exp) f = 
  let rec_f = apply_one_exp (fr,t) in
  match f with
  | BForm (bf, lbl) -> BForm (b_apply_one_exp (fr, t) bf, lbl)
  | And (p1, p2, pos) -> And (rec_f p1,rec_f p2, pos)
  | AndList b -> AndList (map_l_snd rec_f b)
  | Or (p1, p2, lbl, pos) -> Or (rec_f p1,rec_f p2,lbl, pos)
  | Not (p, lbl, pos) -> Not (rec_f p,lbl, pos)
  | Forall (v, qf, lbl, pos) ->
    if eq_spec_var v fr then f
    else Forall (v, rec_f qf,lbl, pos)
  | Exists (v, qf, lbl, pos) ->
    if eq_spec_var v fr then f
    else Exists (v, rec_f qf, lbl, pos)

and b_apply_one_exp (fr, t) bf =
  let (pf,il) = bf in
  let npf = let rec helper pf = 
              match pf with
              | Frm (fv,p) -> if eq_spec_var fv fr then
                  match t with
                  | Var (t,_) -> Frm (t,p)
                  | _ -> failwith ("Presburger.b_apply_one_exp: attempting to substitute arithmetic term for boolean var")
                else pf
              | BConst _ -> pf
              | XPure _ -> pf
              | BVar (bv, pos) -> pf
              | Lt (a1, a2, pos) -> Lt (e_apply_one_exp (fr, t) a1,
                                        e_apply_one_exp (fr, t) a2, pos)
              | Lte (a1, a2, pos) -> Lte (e_apply_one_exp (fr, t) a1,
                                          e_apply_one_exp (fr, t) a2, pos)
              | Gt (a1, a2, pos) -> Gt (e_apply_one_exp (fr, t) a1,
                                        e_apply_one_exp (fr, t) a2, pos)
              | Gte (a1, a2, pos) -> Gte (e_apply_one_exp (fr, t) a1,
                                          e_apply_one_exp (fr, t) a2, pos)
              | SubAnn (a1, a2, pos) -> SubAnn (e_apply_one_exp (fr, t) a1,
                                                e_apply_one_exp (fr, t) a2, pos)
              | Eq (a1, a2, pos) ->
    (*
  		if (eq_b_formula bf (mkEq (mkVar fr pos) t pos)) then
  			bf
  		else*)
                Eq (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
              | Neq (a1, a2, pos) -> Neq (e_apply_one_exp (fr, t) a1,
                                          e_apply_one_exp (fr, t) a2, pos)
              | EqMax (a1, a2, a3, pos) -> EqMax (e_apply_one_exp (fr, t) a1,
                                                  e_apply_one_exp (fr, t) a2,
                                                  e_apply_one_exp (fr, t) a3, pos)
              | EqMin (a1, a2, a3, pos) -> EqMin (e_apply_one_exp (fr, t) a1,
                                                  e_apply_one_exp (fr, t) a2,
                                                  e_apply_one_exp (fr, t) a3, pos)
              | BagIn (v, a1, pos) -> pf
              | BagNotIn (v, a1, pos) -> pf
              (* is it ok?... can i have a set of boolean values?... don't think so... *)
              | BagSub (a1, a2, pos) -> BagSub (a1, e_apply_one_exp (fr, t) a2, pos)
              | BagMax (v1, v2, pos) -> pf
              | BagMin (v1, v2, pos) -> pf
              (* | VarPerm (ct,ls,pos) -> pf (*Do not substitute, ls is the list of variable names*) *)
              | ListIn (a1, a2, pos) -> pf
              | ListNotIn (a1, a2, pos) -> pf
              | ListAllN (a1, a2, pos) -> pf
              | ListPerm (a1, a2, pos) -> pf
              | RelForm (r, args, pos) -> RelForm (r, e_apply_one_list_exp (fr, t) args, pos) (* An Hoa *)
              | ImmRel (r, cond, pos) -> ImmRel (helper r, cond, pos)
              | LexVar t_info -> 
                LexVar { t_info with
                         lex_ann = map_term_ann (apply_one_exp (fr, t)) (e_apply_one_exp (fr, t)) t_info.lex_ann;
                         lex_exp = e_apply_one_list_exp (fr, t) t_info.lex_exp; 
                         lex_tmp = e_apply_one_list_exp (fr, t) t_info.lex_tmp; }
    in helper pf
  in (npf,il)

and e_apply_one_exp (fr, t) e = match e with
  | Null _ | IConst _ | InfConst _ | NegInfConst _ | FConst _| AConst _ | Tsconst _ -> e
  | Bptriple _ -> e
  | Var (sv, pos) -> if eq_spec_var sv fr then t else e
  | Level (sv, pos) -> if eq_spec_var sv fr then t else e
  | Tup2 ((a1, a2), pos) -> Tup2 ((e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2), pos)
  | Add (a1, a2, pos) -> Add (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | Subtract (a1, a2, pos) -> Subtract (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | Mult (a1, a2, pos) -> Mult (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | Div (a1, a2, pos) -> Div (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | Max (a1, a2, pos) -> Max (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | Min (a1, a2, pos) -> Min (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | TypeCast (ty, a, pos) -> TypeCast (ty, e_apply_one_exp (fr, t) a, pos)
  | Bag (alist, pos) -> Bag ((e_apply_one_list_exp (fr, t) alist), pos)
  | BagUnion (alist, pos) -> BagUnion ((e_apply_one_list_exp (fr, t) alist), pos)
  | BagIntersect (alist, pos) -> BagIntersect ((e_apply_one_list_exp (fr, t) alist), pos)
  | BagDiff (a1, a2, pos) -> BagDiff (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | List (alist, pos) -> List ((e_apply_one_list_exp (fr, t) alist), pos)
  | ListAppend (alist, pos) -> ListAppend ((e_apply_one_list_exp (fr, t) alist), pos)
  | ListCons (a1, a2, pos) -> ListCons (e_apply_one_exp (fr, t) a1, e_apply_one_exp (fr, t) a2, pos)
  | ListHead (a1, pos) -> ListHead (e_apply_one_exp (fr, t) a1, pos)
  | ListTail (a1, pos) -> ListTail (e_apply_one_exp (fr, t) a1, pos)
  | ListLength (a1, pos) -> ListLength (e_apply_one_exp (fr, t) a1, pos)
  | ListReverse (a1, pos) -> ListReverse (e_apply_one_exp (fr, t) a1, pos)
  | Func (a, i, pos) -> 
    let a1 = 
      if eq_spec_var a fr then 
        (match t with 
         | Var (s,_) -> s
         | _ -> failwith "Can only substitute ranking variable by ranking variable\n")  
      else a 
    in
    Func (a1, e_apply_one_list_exp (fr, t) i, pos)
  | ArrayAt (a, i, pos) -> 
    let a1 = if eq_spec_var a fr then (match t with 
        | Var (s,_) -> s
        | _ -> failwith "Can only substitute array variable by array variable\n")  else a in
    ArrayAt (a1, e_apply_one_list_exp (fr, t) i, pos) (* An Hoa : BUG DETECTED *)
  | Template tp -> Template { tp with 
                              templ_args = e_apply_one_list_exp (fr, t) tp.templ_args;
                              templ_body = map_opt (e_apply_one_exp (fr, t)) tp.templ_body; }

and e_apply_one_list_exp (fr, t) alist = match alist with
  |[] -> []
  |a :: rest -> (e_apply_one_exp (fr, t) a) :: (e_apply_one_list_exp (fr, t) rest)

(******************************************************************************************************************
   	05.06.2008
   	Utilities for simplifications:
   	- we do some basic simplifications: eliminating identities where the LHS = RHS
 ******************************************************************************************************************)
and elim_idents (f : formula) : formula = 
  let pr = !print_formula in
  Debug.no_1 "elim_idents" pr pr elim_idents_x f 

and elim_idents_x (f : formula) : formula = match f with
  | And (f1, f2, pos) -> mkAnd (elim_idents_x f1) (elim_idents_x f2) pos
  | AndList b->AndList (map_l_snd elim_idents_x b)
  | Or (f1, f2, lbl, pos) -> mkOr (elim_idents_x f1) (elim_idents_x f2) lbl pos
  | Not (f1, lbl, pos) -> mkNot (elim_idents_x f1) lbl pos
  | Forall (sv, f1, lbl, pos) -> mkForall [sv] (elim_idents_x f1) lbl pos
  | Exists (sv, f1, lbl, pos) -> mkExists [sv] (elim_idents_x f1) lbl pos
  | BForm (f1,lbl) -> BForm(elim_idents_b_formula f1, lbl)

(* remove trivial idents such as 
   x=x -> true 
   x!=x -> false
*)
and elim_idents_b_formula (f : b_formula) : b_formula =
  let (pf,il) = f in
  let npf = match pf with
    | Lte (e1, e2, pos)
    | Gte (e1, e2, pos)
    | Eq (e1, e2, pos) ->
      if (eq_exp_no_aset e1 e2) then BConst(true, pos)
      else pf
    | Neq (e1, e2, pos)
    | Lt (e1, e2, pos)
    | Gt (e1, e2, pos) ->
      if (eq_exp_no_aset e1 e2) then BConst(false, pos)
      else pf
    | _ -> pf
  in (npf,il)

(*
let combine_branch b (f, l) =
  match b with 
  | "" -> f
  | s -> try And (f, List.assoc b l, no_pos) with Not_found -> f
;;

let drop_varperm_formula (f0 : formula) : formula =
Debug.no_1 "drop_varperm_formula" !print_formula !print_formula
drop_varperm_formula f0
*)

let wrap_exists_svl f evars = mkExists evars f None no_pos

(* let wrap_exists_svl_new_x f evars = *)
(*   let pos =pos_of_formula f in *)
(*   (\* partition f into dependent vs. independent evars *\) *)
(*   let dep_ps, indep_ps = List.partition (fun p -> *)
(*       intersect_svl (fv p) evars !=[] *)
(*   ) (list_of_conjs f) in *)
(*   let dep_quan_p = mkExists evars (conj_of_list dep_ps pos) None pos in *)
(*   mkAnd (conj_of_list indep_ps pos) dep_quan_p pos *)

let wrap_exists_svl f evars =
  Debug.no_2 "wrap_exists_svl" !print_formula !print_svl !print_formula
    wrap_exists_svl f evars
(*
let merge_branches_with_common l1 l2 cf evars =
  let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
  let wrap_exists (l,f) = (l, mkExists evars f None no_pos) in 
  let map_fun branch =
    try 
      let l1 = List.assoc branch l1 in
      try
        let l2 = List.assoc branch l2 in
        (branch, mkAnd cf (mkAnd l1 l2 no_pos) no_pos)
      with Not_found -> (branch, mkAnd cf l1 no_pos)
    with Not_found -> (branch, mkAnd cf (List.assoc branch l2) no_pos)
  in
  List.map (fun c->wrap_exists(map_fun c)) branches
;;


let merge_branches l1 l2 =
  let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
  let map_fun branch =
    try 
      let l1 = List.assoc branch l1 in
      try
        let l2 = List.assoc branch l2 in
        (branch, mkAnd l1 l2 no_pos)
      with Not_found -> (branch, l1)
    with Not_found -> (branch, List.assoc branch l2)
  in
  List.map map_fun branches
;;

let or_branches_old l1 l2 =
  let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
  let map_fun branch =
    try 
      let l1 = List.assoc branch l1 in
      try
        let l2 = List.assoc branch l2 in
        (branch, mkOr l1 l2 None no_pos)
      with Not_found -> (branch, l1)
    with Not_found -> (branch, List.assoc branch l2)
  in
  List.map map_fun branches
;;

let or_branches l1 l2 =
  let branches = Gen.BList.remove_dups_eq (=) (fst (List.split l1) @ (fst (List.split l2))) in
  let map_fun branch =
    try 
      let l1 = List.assoc branch l1 in
      try
        let l2 = List.assoc branch l2 in
        (branch, mkOr l1 l2 None no_pos)
      with Not_found -> (branch, mkTrue no_pos)
    with Not_found -> (branch, mkTrue no_pos )
  in
  List.map map_fun branches
;;

let add_to_branches label form branches =
  try 
    (label, (And (form, List.assoc label branches, no_pos))) :: (List.remove_assoc label branches) 
  with Not_found -> (label, form) :: branches
;;
 *)
let rec drop_disjunct (f:formula) : formula = 
  match f with
  | BForm _ -> f
  | And (f1,f2,l) -> mkAnd (drop_disjunct f1) (drop_disjunct f2) l
  | AndList b ->AndList (map_l_snd drop_disjunct b)
  | Or (_,_,_,l) -> mkTrue l
  | Not (f,_,_) -> f  (* Not ((drop_disjunct f),l) TODO: investigate if f is the proper return value, in conjunction with case inference*)
  | Forall (q,f,lbl,l) -> Forall (q,(drop_disjunct f),lbl, l)
  | Exists (q,f,lbl,l) -> Exists (q,(drop_disjunct f),lbl, l) 

and float_out_quantif f = match f with
  | BForm b-> (f,[],[])
  | And (b1,b2,l) -> 
    let l1,l2,l3 = float_out_quantif b1 in
    let q1,q2,q3 = float_out_quantif b2 in
    ((mkAnd l1 q1 l), l2@q2, l3@q3)
  | AndList b-> 
    let (b1,l1,l2) = List.fold_left (fun (a1,a2,a3) (l,c)-> 
        let l1,l2,l3 = float_out_quantif c in
        (l,c)::a1,l2@a2,l3@a3)  ([],[],[]) b in
    (AndList b1, l1, l2)
  | Or (b1,b2,lbl,l) ->
    let l1,l2,l3 = float_out_quantif b1 in
    let q1,q2,q3 = float_out_quantif b2 in
    ((mkOr l1 q1 lbl l), l2@q2, l3@q3)
  | Not (b,lbl,l) ->
    let l1,l2,l3 = float_out_quantif b in
    (Not (l1,lbl,l), l2,l3)
  | Forall (q,b,lbl,l)->
    let l1,l2,l3 = float_out_quantif b in
    (l1,q::l2,l3)
  | Exists (q,b,lbl,l)->
    let l1,l2,l3 = float_out_quantif b in
    (l1,l2,q::l3)

and check_not (f:formula):formula = 
  let rec inner (f:formula):formula*bool = match f with
    | BForm b -> (f,false)
    | And (b1,b2,l) -> 
      let l1,r1 = inner b1 in
      let l2,r2 = inner b2 in
      ((mkAnd l1 l2 l),r1&&r2)
    | Or (b1,b2,lbl,l) -> 
      let l1,r1 = inner b1 in
      let l2,r2 = inner b2 in
      ((mkOr l1 l2 lbl l),r1&&r2)
    | Not (b,lbl,l) -> begin
        match b with
        | BForm _ -> (f,false)
        | And (b1,b2,l) -> 
          let l1,_ = inner (Not (b1,lbl,l)) in
          let l2,_ = inner (Not (b2,lbl,l)) in
          ((mkOr l1 l2 lbl l),true)
        | Or (b1,b2,lbl2,l) ->
          let l1,_ = inner (Not (b1,lbl,l)) in
          let l2,_ = inner (Not (b2,lbl,l)) in
          ((mkAnd l1 l2 l),true)
        | Not (b,lbl,l) ->
          let l1,r1 = inner b in
          (l1,true)
        | _ -> (f,false)
      end
    | _ ->  (f,false) in
  let f,r = inner f in
  if r then check_not f
  else f 

and of_interest (e1:exp) (e2:exp) (interest_vars:spec_var list):bool = 
  let is_simple e = match e with
    | Null _ 
    | Var _ 
    | Level _ 
    | IConst _ 
    | InfConst _ 
    | NegInfConst _ 
    | AConst _
    | Tsconst _
    | FConst _ -> true
    | Bptriple _ -> false (*TOCHECK*)
    | Tup2 ((e1,e2),_)
    | Add (e1,e2,_)
    | Subtract (e1,e2,_) -> false
    | Mult _
    | Div _
    | Max _ 
    | Min _
    | TypeCast _
    | Bag _
    | BagUnion _
    | BagIntersect _ 
    | BagDiff _
    | List _
    | ListCons _
    | ListTail _
    | ListAppend _
    | ListReverse _
    | ListHead _
    | ListLength _ 
    | Func _
    | Template _ 
    | ArrayAt _ -> false (* An Hoa *) in
  ((is_simple e1)&& match e2 with
    | Var (v1,l)-> List.exists (fun c->eq_spec_var c v1) interest_vars
    | _ -> false
  )||((is_simple e2)&& match e1 with
    | Var (v1,l)-> List.exists (fun c->eq_spec_var c v1) interest_vars
    | _ -> false)


and drop_null (f:formula) self neg:formula = 
  let helper(f:b_formula) neg:b_formula =
    let (pf,il) = f in
    let npf = match pf with
      | Eq (e1,e2,l) -> if neg then pf
        else begin match (e1,e2) with
          | (Var(self,_),Null _ )
          | (Null _ ,Var(self,_))-> BConst (true,l)
          | _ -> pf end
      | Neq (e1,e2,l) -> if (not neg) then pf
        else begin match (e1,e2) with
          | (Var(self,_),Null _ )
          | (Null _ ,Var(self,_))-> BConst (true,l)
          | _ -> pf end
      | _ -> pf in
    (npf,il) in
  match f with
  | BForm (b,lbl)-> BForm (helper b neg , lbl)
  | And (b1,b2,l) -> And ((drop_null b1 self neg),(drop_null b2 self neg),l)
  | AndList b -> AndList (map_l_snd (fun c-> drop_null c self neg) b)
  | Or _ -> f
  | Not (b,lbl,l)-> Not ((drop_null b self (not neg)),lbl,l)
  | Forall (q,f,lbl,l) -> Forall (q,(drop_null f self neg),lbl,l)
  | Exists (q,f,lbl,l) -> Exists (q,(drop_null f self neg),lbl,l)

and add_null f self : formula =
  mkAnd f (BForm ((mkEq_b (Var (self,no_pos)) (Null no_pos) no_pos, None))) no_pos
(*to fully extend*)
(* TODO: double check this func *)

and rel_compute e1 e2:constraint_rel = match (e1,e2) with
  | Null _, Null _ -> Equal
  | Null _, Var (v1,_)  -> if (String.compare (name_of_spec_var v1)"null")=0 then Equal else Unknown
  | Null _, IConst (i,_) -> if i=0 then Equal else Contradicting
  | Var (v1,_), Null _ -> if (String.compare (name_of_spec_var v1)"null")=0 then Equal else Unknown
  | Var (v1,_), Var (v2,_) -> if (String.compare (name_of_spec_var v1)(name_of_spec_var v2))=0 then Equal else Unknown
  | Var _, IConst _ -> Unknown
  | IConst (i,_) , Null _ -> if i=0 then Equal else Contradicting
  | IConst _ ,Var _ -> Unknown
  | IConst (i1,_) ,IConst (i2,_) -> if (i1<i2) then Subsumed else if (i1=i2) then Equal else Subsuming
  | _ -> Unknown

and compute_constraint_relation_x f_sat f_imply ((a1,a3,a4):(int* b_formula *(spec_var list))) ((b1,b3,b4):(int* b_formula *(spec_var list)))
  :constraint_rel =
  let r = match (fst a3,fst b3) with
    | ((BVar v1),(BVar v2))-> if (v1=v2) then Equal else Unknown
    | (Neq (e1,e2,_), Neq (d1,d2,_))
    | (Eq (e1,e2,_), Eq  (d1,d2,_)) -> begin match ((rel_compute e1 d1),(rel_compute e2 d2)) with
        | Equal,Equal-> Equal
        | _ -> match ((rel_compute e1 d2),(rel_compute e2 d1)) with
          | Equal,Equal-> Equal
          | _ ->  Unknown end
    | (Eq  (e1,e2,_), Neq (d1,d2,_))
    | (Neq (e1,e2,_), Eq  (d1,d2,_)) ->  begin
        match ((rel_compute e1 d1),(rel_compute e2 d2)) with
        | Equal,Equal-> Contradicting
        | _ -> match ((rel_compute e1 d2),(rel_compute e2 d1)) with
          | Equal,Equal-> Contradicting
          | _ ->  Unknown end
    | _ -> Unknown in
  match r with
  | Unknown ->
    if equalBFormula_f eq_spec_var a3 b3 then Equal
    else if f_sat (mkAnd (BForm (a3,None)) (BForm (b3,None)) no_pos) then
      (match f_imply a3 b3,f_imply b3 a3 with
       | true, true -> Equal
       | true, false -> Subsuming
       | false, true -> Subsumed
       | false, false -> Unknown)
    else Contradicting
  | _ -> r
(*| (Lt (e1,e2,_), Lt  (d1,d2,_))
  | (Lt (e1,e2,_), Lte (d1,d2,_))
  | (Lt (e1,e2,_), Eq  (d1,d2,_))
  | (Lt (e1,e2,_), Neq (d1,d2,_))
  | (Lte (e1,e2,_), Lt  (d1,d2,_))
  | (Lte (e1,e2,_), Lte (d1,d2,_))
  | (Lte (e1,e2,_), Eq  (d1,d2,_))
  | (Lte (e1,e2,_), Neq (d1,d2,_))
  | (Eq (e1,e2,_), Lt  (d1,d2,_))
  | (Eq (e1,e2,_), Lte (d1,d2,_))
  | (Neq (e1,e2,_), Lt  (d1,d2,_))
  | (Neq (e1,e2,_), Lte (d1,d2,_)) -> Unknown*)

and compute_constraint_relation f_sat f_imply a b =
  let pr1 = pr_triple string_of_int !print_b_formula !print_svl in
  let pr r = match r with | Unknown -> "Unk" | Subsumed -> "<" | Subsuming -> ">" | Equal -> "=" | Contradicting -> "Contr" in
  Debug.no_2 "compute_constraint_relation" pr1 pr1 pr (compute_constraint_relation_x f_sat f_imply) a b

and b_form_list f: b_formula list = match f with
  | BForm (b,_) -> [b]
  | And (b1,b2,_)-> (b_form_list b1)@(b_form_list b2)
  | AndList b -> fold_l_snd b_form_list b
  | Or _ -> []
  | Not _ -> []
  | Forall (_,f,_,_)
  | Exists (_,f,_,_) -> (b_form_list f)

and simp_mult (e: exp) : exp =
  let pr = !print_exp in
  Debug.no_1 "simp_mult" pr pr simp_mult_x e

and simp_mult_x (e : exp) :  exp =
  let rec normalize_add m lg (x: exp):  exp =
    match x with
    |  Add (e1, e2, l) ->
      let t1 = normalize_add m l e2 in normalize_add (Some t1) l e1
    | _ -> (match m with | None -> x | Some e ->  Add (e, x, lg)) in
  let rec acc_mult m e0 =
    match e0 with
    | Null _
    | Tsconst _
    | Bptriple _
    | NegInfConst _
    | AConst _ -> e0
    |  Tup2 ((e1, e2), l) ->
      Tup2 ((acc_mult m e1, acc_mult m e2), l)
    | Var (v, l) ->
      (match m with
       | None -> e0
       | Some c ->  Mult (IConst (c, l), e0, l))
    | Level (v, l) ->
      (match m with
       | None -> e0
       | Some c ->  Mult (IConst (c, l), e0, l))
    (* AS : To check what this method is doing *)
    | InfConst  (v,l) -> (match m with 
        | None -> e0
        | Some c ->  Mult (IConst (c, l), e0, l))
    | IConst (v, l) ->
      (match m with
       | None -> e0
       | Some c ->  IConst (c * v, l))
    | FConst (v, l) ->
      (match m with
       | None -> e0
       | Some c -> FConst (v *. (float_of_int c), l))
    |  Add (e1, e2, l) ->
      normalize_add None l ( Add (acc_mult m e1, acc_mult m e2, l))
    |  Subtract (e1, e2, l) ->
      normalize_add None l
        ( Add (acc_mult m e1,
               acc_mult
                 (match m with | None -> Some (- 1) | Some c -> Some (- c)) e2,
               l))
    | Mult (e1, e2, l) -> Mult (acc_mult m e1, acc_mult None e2, l)
    | Div (e1, e2, l) -> Div (acc_mult m e1, acc_mult None e2, l)
    |  Max (e1, e2, l) ->
      Error.report_error
        {
          Error.error_loc = l;
          Error.error_text =
            "got Max !! (Should have already been simplified )";
        }
    |  Min (e1, e2, l) ->
      Error.report_error
        {
          Error.error_loc = l;
          Error.error_text =
            "got Min !! (Should have already been simplified )";
        }
    | TypeCast (ty, e1, l) -> TypeCast (ty, acc_mult m e1, l)
    |  Bag (el, l) ->  Bag (List.map (acc_mult m) el, l)
    |  BagUnion (el, l) ->  BagUnion (List.map (acc_mult m) el, l)
    |  BagIntersect (el, l) -> BagIntersect (List.map (acc_mult m) el, l)
    |  BagDiff (e1, e2, l) -> BagDiff (acc_mult m e1, acc_mult m e2, l)
    |  List (_, l)
    |  ListAppend (_, l)
    |  ListCons (_, _, l)
    |  ListTail (_, l)
    |  ListReverse (_, l)
    |  ListHead (_, l)
    |  ListLength (_, l)
    |  Func (_, _, l)
    | Template { templ_pos = l; }
    |  ArrayAt (_, _, l) ->
      match m with | None -> e0 | Some c ->  Mult (IConst (c, l), e0, l)

  in acc_mult None e

and split_sums (e :  exp) : (( exp option) * ( exp option)) =
  let pr1 = pr_opt !print_exp in
  (* Debug.no_1 "split_sums" !print_exp (pr_pair pr1 pr1) *)
    split_sums_x e

and split_sums_x (e :  exp) : (( exp option) * ( exp option)) =
  match e with
  |  Null _
  |  Var _
  |  Level _
  |  Tsconst _
  |  Bptriple _
  |  Tup2 _ (*TOCHECK*)
  |  InfConst _
  |  NegInfConst _
  |  AConst _ -> ((Some e), None)
  |  IConst (v, l) ->
    if v >= 0 then
      ((Some e), None)
    else
      (* if v < 0 then *)
      (None, (Some ( IConst (- v, l))))
  (* else (None, None) *)
  | FConst (v, l) ->
    if v >= 0.0 then
      ((Some e), None)
    else
      (* if v < 0.0 then *)
      ((None, (Some (FConst (-. v, l)))))
  (* else (None, None) *)
  |  Add (e1, e2, l) ->
    let (ts1, tm1) = split_sums e1 in
    let (ts2, tm2) = split_sums e2 in
    let tsr =
      (match (ts1, ts2) with
       | (None, None) -> None
       | (None, Some r1) -> ts2
       | (Some r1, None) -> ts1
       | (Some r1, Some r2) -> Some ( Add (r1, r2, l))) in
    let tmr =
      (match (tm1, tm2) with
       | (None, None) -> None
       | (None, Some r1) -> tm2
       | (Some r1, None) -> tm1
       | (Some r1, Some r2) -> Some ( Add (r1, r2, l)))
    in (tsr, tmr)
  |  Subtract (e1, e2, l) ->
    Error.report_error
      {
        Error.error_loc = l;
        Error.error_text =
          "got subtraction !! (Should have already been simplified )";
      }
  | Mult (e1, e2, l) ->
    let ts1, tm1 = split_sums e1 in
    let ts2, tm2 = split_sums e2 in
    let r =
      match ts1, tm1, ts2, tm2 with
      | None, None, _, _ -> None, None
      | _, _, None, None -> None, None
      | Some r1, None, Some r2, None -> Some (Mult (r1, r2, l)), None
      | Some r1, None, None, Some r2 -> None, Some (Mult (r1, r2, l))
      | None, Some r1, Some r2, None -> None, Some (Mult (r1, r2, l))
      | None, Some r1, None, Some r2 -> Some (Mult (r1, r2, l)), None
      | _ -> ((Some e), None) (* Undecidable cases *)
    in r
  | Div (e1, e2, l) ->
    (* IMHO, this implementation is useless *)
    let ts1, tm1 = split_sums e1 in
    let ts2, tm2 = split_sums e2 in
    let r =
      match ts1, tm1, ts2, tm2 with
      | None, None, _, _ -> None, None
      | _, _, None, None -> failwith "[cpure.ml] split_sums: divide by zero"
      | Some r1, None, Some r2, None -> Some (Div (r1, r2, l)), None
      | Some r1, None, None, Some r2 -> None, Some (Div (r1, r2, l))
      | None, Some r1, Some r2, None -> None, Some (Div (r1, r2, l))
      | None, Some r1, None, Some r2 -> Some (Div (r1, r2, l)), None
      | _ -> Some e, None
    in r
  |  Max (e1, e2, l) ->
    Error.report_error
      {
        Error.error_loc = l;
        Error.error_text =
          "got Max !! (Should have already been simplified )";
      }
  |  Min (e1, e2, l) ->
    Error.report_error
      {
        Error.error_loc = l;
        Error.error_text =
          "got Min !! (Should have already been simplified )";
      }
  |  TypeCast _ -> ((Some e), None)
  |  Bag (e1, l) -> ((Some e), None)
  |  BagUnion (e1, l) -> ((Some e), None)
  |  BagIntersect (e1, l) -> ((Some e), None)
  |  BagDiff (e1, e2, l) -> ((Some e), None)
  |  List (el, l) -> ((Some e), None)
  |  ListAppend (el, l) -> ((Some e), None)
  |  ListCons (e1, e2, l) -> ((Some e), None)
  |  ListHead (e1, l) -> ((Some e), None)
  |  ListTail (e1, l) -> ((Some e), None)
  |  ListLength (e1, l) -> ((Some e), None)
  |  ListReverse (e1, l) -> ((Some e), None)
  |  Func (id, es, l) -> ((Some e), None)
  | Template _ -> ((Some e), None)
  |  ArrayAt (a, i, l) -> ((Some e), None) (* An Hoa *)

(* 
   lhs-lsm = rhs-rsm   ==> lhs+rsm = rhs+lsm 
*)
and move_lr (lhs :  exp option) (lsm :  exp option)
    (rhs :  exp option) (rsm :  exp option) l :
  ( exp *  exp) =
  let nl =
    match (lhs, rsm) with
    | (None, None) ->  IConst (0, l)
    | (Some e, None) -> e
    | (None, Some e) -> e
    | (Some e1, Some e2) ->  Add (e1, e2, l) in
  let nr =
    match (rhs, lsm) with
    | (None, None) ->  IConst (0, l)
    | (Some e, None) -> e
    | (None, Some e) -> e
    | (Some e1, Some e2) ->  Add (e1, e2, l)
  in (nl, nr)

(* 
   lhs-lsm = max(rhs-rsm,qhs-qsm) 
   ==> lhs+rsm+qsm = max(rhs+lsm+qsm,qhs+lsm+rsm) 
*)
and move_lr3 (lhs :  exp option) (lsm :  exp option)
    (rhs :  exp option) (rsm :  exp option) (qhs :  exp option) (qsm :  exp option) loc :
  ( exp *  exp * exp) =
  let rec add e ls = match e,ls with
    | None,[] -> IConst (0, loc)
    | Some e,[] -> e
    | None,l::ls ->  add (Some l) ls 
    | Some e,l::ls ->  add (Some (Add (e,l,loc))) ls in
  let rl,ql = match lsm with
    | None -> [],[]
    | Some e -> [e],[e] in
  let ll,ql = match rsm with
    | None -> [],ql
    | Some e -> [e],e::ql in
  let ll,rl = match qsm with
    | None -> ll,rl
    | Some e -> e::ll,e::rl in
  (add lhs ll, add rhs rl, add qhs ql)

and purge_mult (e: exp) : exp =
  let pr = !print_exp in
  (* Debug.no_1 "purge_mult" pr pr *) purge_mult_x e

(* TODO : must elim some multiply for MONA *)
and purge_mult_x (e :  exp):  exp = match e with
  |  Null _ 
  |  Var _ 
  |  Level _ 
  |  IConst _ 
  |  AConst _ 
  | InfConst _
  | NegInfConst _
  | Tsconst _
  | Bptriple _
  | Tup2 _
  | FConst _ -> e
  |  Add (e1, e2, l) ->  Add((purge_mult e1), (purge_mult e2), l)
  |  Subtract (e1, e2, l) ->  Subtract((purge_mult e1), (purge_mult e2), l)
  | Mult (e1, e2, l) ->
    let t1 = purge_mult e1 in
    let t2 = purge_mult e2 in
    begin
      match t1 with
      | IConst (v1, _) -> 
        if (v1 = 0) then t1 
        else if (v1 = 1) then t2 
        else begin 
          match t2 with
          | IConst (v2, _) -> IConst (v1 * v2, l)
          | FConst (v2, _) -> FConst ((float_of_int v1) *. v2, l)
          | _ -> if (v1=2) then Add(t2,t2,l)
            else Mult (t1, t2, l)
        end
      | FConst (v1, _) ->
        if (v1 = 0.0) then t1 
        else begin
          match t2 with
          | IConst (v2, _) -> FConst (v1 *. (float_of_int v2), l)
          | FConst (v2, _) -> FConst (v1 *. v2, l)
          | _ -> Mult (t1, t2, l)
        end
      | _ -> 
        begin
          match t2 with
          | IConst (v2, _) -> 
            if (v2 = 0) then t2 
            else if (v2 = 1) then t1 
            else if (v2 = 2) then Add(t1,t1,l)
            else Mult (t1, t2, l) 
          | FConst (v2, _) ->
            if (v2 = 0.0) then t2 
            else Mult (t1, t2, l)
          | _ -> Mult (t1, t2, l) 
        end
    end
  | Div (e1, e2, l) ->
    let t1 = purge_mult e1 in
    let t2 = purge_mult e2 in
    if (!Globals.no_float_simpl) then
      (*Avoid losing precision, e.g. 1/3 = 0.33333*)
      Div (t1, t2, l)
    else
      begin
        match t1 with
        | IConst (v1, _) ->
          if (v1 = 0) then FConst (0.0, l) 
          else begin
            match t2 with
            | IConst (v2, _) ->
              if (v2 = 0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else FConst((float_of_int v1) /. (float_of_int v2), l)
            | FConst (v2, _) ->
              if (v2 = 0.0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else FConst((float_of_int v1) /. v2, l)
            | _ -> Div (t1, t2, l) 
          end
        | FConst (v1, _) ->
          if (v1 = 0.0) then FConst (0.0, l)
          else begin
            match t2 with
            | IConst (v2, _) ->
              if (v2 = 0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else FConst(v1 /. (float_of_int v2), l)
            | FConst (v2, _) ->
              if (v2 = 0.0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else FConst(v1 /. v2, l)
            | _ -> Div (t1, t2, l)
          end
        | _ -> 
          begin
            match t2 with
            | IConst (v2, _) ->
              if (v2 = 0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else Div (t1, t2, l)
            | FConst (v2, _) ->
              if (v2 = 0.0) then
                Error.report_error {
                  Error.error_loc = l;
                  Error.error_text = "divided by zero";
                }
              else Div (t1, t2, l)
            | _ -> Div (t1, t2, l)
          end
      end
  |  Max (e1, e2, l) ->  Max((purge_mult e1), (purge_mult e2), l)
  |  Min (e1, e2, l) ->  Min((purge_mult e1), (purge_mult e2), l)
  |  TypeCast (ty, e1, l) -> TypeCast (ty, purge_mult e1, l)
  |  Bag (el, l) ->  Bag ((List.map purge_mult el), l)
  |  BagUnion (el, l) ->  BagUnion ((List.map purge_mult el), l)
  |  BagIntersect (el, l) ->  BagIntersect ((List.map purge_mult el), l)
  |  BagDiff (e1, e2, l) ->  BagDiff ((purge_mult e1), (purge_mult e2), l)
  |  List (el, l) -> List ((List.map purge_mult el), l)
  |  ListAppend (el, l) -> ListAppend ((List.map purge_mult el), l)
  |  ListCons (e1, e2, l) -> ListCons (purge_mult e1, purge_mult e2, l)
  |  ListHead (e, l) -> ListHead (purge_mult e, l)
  |  ListTail (e, l) -> ListTail (purge_mult e, l)
  |  ListLength (e, l) -> ListLength (purge_mult e, l)
  |  ListReverse (e, l) -> ListReverse (purge_mult e, l)
  |  Func (id, es, l) -> Func (id, List.map purge_mult es, l)
  | Template t -> Template { t with 
                             templ_args = List.map purge_mult t.templ_args;
                             templ_body = map_opt purge_mult t.templ_body; }
  |  ArrayAt (a, i, l) -> ArrayAt (a, List.map purge_mult i, l) (* An Hoa *)

and b_form_simplify (pf : b_formula) :  b_formula =   
  Debug.no_1 "b_form_simplify " !print_b_formula !print_b_formula 
    b_form_simplify_x pf

and b_form_simplify_x (b:b_formula) :b_formula = 
  let do_all e1 e2 l =
    let t1 = simp_mult e1 in
    let t2 = simp_mult e2 in
    let t1 = purge_mult t1 in
    let t2 = purge_mult t2 in
    let (lhs, lsm) = split_sums t1 in
    let (rhs, rsm) = split_sums t2 in
    let (lh, rh) = move_lr lhs lsm rhs rsm l in
    (* purge_mult will convert 1*x => x and 0*x => 0
       but this code seems inefficient *)
    let lh = purge_mult lh in
    let rh = purge_mult rh in
    (lh, rh) in
  let build_eq lhs rhs = 
    (* to simplify to v=rhs *)
    (lhs,rhs) in
  let do_all_eq e1 e2 l = 
    let (lhs,rhs) as r = do_all e1 e2 l in
    let new_r = 
      if !Globals.non_linear_flag then build_eq lhs rhs 
      else r in
    new_r in
  let do_all_eq e1 e2 l = 
    let pr = !print_exp in
      Debug.no_2 "do_all_eq" pr pr (pr_pair pr pr) (fun _ _ -> do_all_eq e1 e2 l) e1 e2
  in
  let do_all3 e1 e2 e3 l =
    let t1 = simp_mult e1 in
    let t2 = simp_mult e2 in
    let t3 = simp_mult e3 in
    let (lhs, lsm) = split_sums t1 in
    let (rhs, rsm) = split_sums t2 in
    let (qhs, qsm) = split_sums t3 in
    let ((lh,rh,qh),flag) =
      match (lhs,rhs,qhs,lsm,rsm,qsm) with
      (* -x = max(-y,-z) ==> x = min(y,z) *)
      | None,None,None,Some lh,Some rh, Some qh -> ((lh,rh,qh),false)
      | _,_,_,_,_,_ -> (move_lr3 lhs lsm rhs rsm qhs qsm l,true) in
    let lh = purge_mult lh in
    let rh = purge_mult rh in
    let qh = purge_mult qh in
    (lh, rh, qh,flag) in
  let do_all3_eq e1 e2 e3 l = 
    let pr = !print_exp in
      Debug.no_3 "do_all3_eq" pr pr pr (pr_quad pr pr pr string_of_bool) (fun _ _ _ -> do_all3 e1 e2 e3 l) e1 e2 e3
  in
  let (pf,il) = b in
  let npf = let rec helper pf = 
              match pf with
              | Frm _
              |  BConst _ 
              |  SubAnn _ | LexVar _ | XPure _
              |  BVar _ -> pf
              |  Lt (e1, e2, l) ->
                let lh, rh = do_all e1 e2 l in
                Lt (lh, rh, l)
              |  Lte (e1, e2, l) ->
                let lh, rh = do_all e1 e2 l in
                Lte (lh, rh, l)
              |  Gt (e1, e2, l) ->
                let lh, rh = do_all e1 e2 l in
                Lt (rh, lh, l)
              |  Gte (e1, e2, l) ->
                let lh, rh = do_all e1 e2 l in
                Lte (rh, lh, l)
              |  Eq (e1, e2, l) ->
                if !perm=Dperm && (perm_bounds e1 || perm_bounds e2) then  BConst (false, l)
                else
                  let lh, rh = x_add do_all_eq e1 e2 l in
                  Eq (lh, rh, l)
              |  Neq (e1, e2, l) ->
                let lh, rh = do_all e1 e2 l in
                Neq (lh, rh, l)
              |  EqMax (e1, e2, e3, l) ->
                let lh,rh,qh,flag = x_add do_all3_eq e1 e2 e3 l in
                if flag then EqMax (lh,rh,qh,l)
                else EqMin (lh,rh,qh,l)
              (* let ne1 = simp_mult e1 in *)
              (* let ne2 = simp_mult e2 in *)
              (* let ne3 = simp_mult e3 in *)
              (* let ne1 = purge_mult ne1 in *)
              (* let ne2 = purge_mult ne2 in *)
              (* let ne3 = purge_mult ne3 in *)
              (* (\*if (!Tpdispatcher.tp == Tpdispatcher.Mona) then*\) *)
              (*      let (s1, m1) = split_sums ne1 in *)
              (*    	let (s2, m2) = split_sums ne2 in *)
              (*    	let (s3, m3) = split_sums ne3 in *)
              (*    	begin *)
              (*    	match (s1, s2, s3, m1, m2, m3) with *)
              (*    		| None, None, None, None, None, None ->  BConst (true, l) *)
              (*    		| Some e11, Some e12, Some e13, None, None, None ->  *)
              (*    			let e11 = purge_mult e11 in *)
              (*    			let e12 = purge_mult e12 in *)
              (*    			let e13 = purge_mult e13 in *)
              (*    			 EqMax (e11, e12, e13, l) *)
              (*    		| None, None, None, Some e11, Some e12, Some e13 ->  *)
              (*    			let e11 = purge_mult e11 in *)
              (*    			let e12 = purge_mult e12 in *)
              (*    			let e13 = purge_mult e13 in *)
              (*    			 EqMin (e11, e12, e13, l) *)
              (*    		| _ ->  *)
              (*    			  EqMax (ne1, ne2, ne3, l) *)
              (*    	end *)
              (*else 
                     EqMax (ne1, ne2, ne3, l)*)
              |  EqMin (e1, e2, e3, l) ->
                let lh,rh,qh,flag = x_add do_all3_eq e1 e2 e3 l in
                if flag then EqMin (lh,rh,qh,l)
                else EqMax (lh,rh,qh,l)
              (* let ne1 = simp_mult e1 in *)
              (* let ne2 = simp_mult e2 in *)
              (* let ne3 = simp_mult e3 in *)
              (* let ne1 = purge_mult ne1 in *)
              (* let ne2 = purge_mult ne2 in *)
              (* let ne3 = purge_mult ne3 in *)
              (* (\*if (!Tpdispatcher.tp == Tpdispatcher.Mona) then*\) *)
              (*      let (s1, m1) = split_sums ne1 in *)
              (*    	let (s2, m2) = split_sums ne2 in *)
              (*    	let (s3, m3) = split_sums ne3 in *)
              (*    	begin *)
              (*    	match (s1, s2, s3, m1, m2, m3) with *)
              (*    		| None, None, None, None, None, None ->  BConst (true, l) *)
              (*    		| Some e11, Some e12, Some e13, None, None, None ->  *)
              (*    				let e11 = purge_mult e11 in *)
              (*    				let e12 = purge_mult e12 in *)
              (*    				let e13 = purge_mult e13 in *)
              (*    				 EqMin (e11, e12, e13, l) *)
              (*    		| None, None, None, Some e11, Some e12, Some e13 ->  *)
              (*    				let e11 = purge_mult e11 in *)
              (*    				let e12 = purge_mult e12 in *)
              (*    				let e13 = purge_mult e13 in *)
              (*    				 EqMax (e11, e12, e13, l) *)
              (*    		| _ ->  EqMin (ne1, ne2, ne3, l) *)
              (*    	end *)
              (*else
                     EqMin (ne1, ne2, ne3, l)*)
              |  BagIn (v, e1, l) ->  BagIn (v, purge_mult (simp_mult e1), l)
              |  BagNotIn (v, e1, l) ->  BagNotIn (v, purge_mult (simp_mult e1), l)
              |  ListIn (e1, e2, l) -> ListIn (purge_mult (simp_mult e1), purge_mult (simp_mult e2), l)
              |  ListNotIn (e1, e2, l) -> ListNotIn (purge_mult (simp_mult e1), purge_mult (simp_mult e2), l)
              |  ListAllN (e1, e2, l) -> ListAllN (purge_mult (simp_mult e1), purge_mult (simp_mult e2), l)
              |  ListPerm (e1, e2, l) -> ListPerm (purge_mult (simp_mult e1), purge_mult (simp_mult e2), l)
              |  BagSub (e1, e2, l) ->
                BagSub (simp_mult e1, simp_mult e2, l)
              |  BagMin _ -> pf
              |  BagMax _ -> pf
              (* |  VarPerm _ -> pf *)
              |  RelForm (v,exs,p) ->  
                let new_exs = List.map (fun e -> purge_mult (simp_mult e)) exs in
                RelForm (v,new_exs,p)
              |  ImmRel (v,cond,p) ->  let new_v = helper v in ImmRel (new_v,cond,p)
    in helper pf
  in (npf,il)

(* a+a    --> 2*a
   1+3    --> 4
   1+x>-2 --> 3+x>0
*)  

and arith_simplify (i:int) (pf : formula) :  formula =
  Debug.no_1 ("arith_simplify LHS") !print_formula !print_formula
    arith_simplify_x pf


and arith_simplify_x (pf : formula) :  formula =
  (* temporarily do not prevent this simplification because it helps
     convert proofs into normal form such as those of Mona (e.g. Mona
     does not allow subtraction*)
  if (not !Globals.allow_norm) && !Globals.allow_inf_qe_coq then pf else
  if !Globals.dis_norm then pf else
    let rec helper pf = match pf with
      |  BForm (b,lbl) -> BForm (x_add_1 b_form_simplify b,lbl)
      |  And (f1, f2, loc) -> And (helper f1, helper f2, loc)
      |  AndList b -> AndList (map_l_snd helper b)
      |  Or (f1, f2, lbl, loc) -> Or (helper f1, helper f2, lbl, loc)
      |  Not (f1, lbl, loc) ->  Not (helper f1, lbl, loc)
      |  Forall (v, f1, lbl, loc) ->  Forall (v, helper f1, lbl, loc)
      |  Exists (v, f1, lbl, loc) ->  Exists (v, helper f1, lbl, loc)
    in helper pf

let get_pure_label n =  match n with
  | And _ 
  | AndList _ ->  None
  | BForm (_,l) 
  | Or (_,_,l,_) 
  | Not (_,l,_) 
  | Forall (_,_,l,_) 
  | Exists (_,_,l,_) -> l

let select zs n = 
  let l = List.length zs in
  (List.nth zs (n mod l))


let rename_labels  e=
  let f_b e = Some e in
  let f_e e = Some e in
  let f_f e = 
    let n_l_f n_l = match n_l with
      | None -> (fresh_branch_point_id "")
      | Some (_,s) -> (fresh_branch_point_id s) in	
    match e with
    | BForm (b,f_l) -> Some (BForm (b,(n_l_f f_l)))
    | And _
    | AndList _ -> None
    | Or (e1,e2,f_l,l) -> (Some (Or (e1,e2,(n_l_f f_l),l)))
    | Not (e1,f_l, l) -> (Some (Not (e1,(n_l_f f_l),l)))
    | Forall (v,e1,f_l, l) -> (Some (Forall (v,e1,(n_l_f f_l),l)))
    | Exists (v,e1,f_l, l) -> (Some (Exists (v,e1,(n_l_f f_l),l)))in			
  transform_formula ((fun _-> None),(fun _-> None), f_f,f_b,f_e) e

let remove_dup_constraints (f:formula):formula = 
  (*let f = elim_idents f in*)
  let l_conj = split_conjunctions f in
  let prun_l = Gen.BList.remove_dups_eq equalFormula l_conj in
  join_conjunctions prun_l

let rec get_head e = match e with 
  | Null _ -> "Null"
  | Var (v,_) -> name_of_spec_var v
  | Level (v,_) -> name_of_spec_var v
  | IConst (i,_)-> string_of_int i
  | InfConst(i,_) -> i
  | NegInfConst(i,_) -> i
  | FConst (f,_) -> string_of_float f
  | AConst (f,_) -> string_of_heap_ann f
  | Tsconst (f,_) -> Tree_shares.Ts.string_of f
  | Bptriple _ -> "Bptriple"
  | Tup2 ((e,_),_)
  | Add (e,_,_) | Subtract (e,_,_) | Mult (e,_,_) | Div (e,_,_) | TypeCast (_, e, _)
  | Max (e,_,_) | Min (e,_,_) | BagDiff (e,_,_) | ListCons (e,_,_)| ListHead (e,_) 
  | ListTail (e,_)| ListLength (e,_) | ListReverse (e,_)  -> get_head e
  | Bag (e_l,_) | BagUnion (e_l,_) | BagIntersect (e_l,_) | List (e_l,_) | ListAppend (e_l,_)-> 
    if (List.length e_l)>0 then get_head (List.hd e_l) else "[]"
  | Func _ -> ""
  | Template _ -> ""
  | ArrayAt (a, i, _) -> "" (* An Hoa *) 

let form_bform_eq (v1:spec_var) (v2:spec_var) =
  Eq(Var(v1,no_pos),Var(v2,no_pos),no_pos)

let form_formula_eq (v1:spec_var) (v2:spec_var) =
  BForm (((form_bform_eq v1 v2), None), None)

let is_zero b =   match b with
  | IConst(0,_) -> true
  | _ -> false

let is_one b =   match b with
  | IConst(1,_) -> true
  | _ -> false

let simple el = List.length el <=1

let addlist_to_exp (el:exp list) : exp = 
  let el = List.sort (fun e1 e2 -> String.compare (get_head e2) (get_head e1)) el in
  match el with
  | [] -> IConst(0,no_pos)
  | e::es -> List.fold_left (fun ac e1 -> Add(e1,ac,no_pos) ) e es 

let e_cmp e1 e2 =  String.compare (get_head e1) (get_head e2) 

let two_args e1 e2 isOne f loc=
  if isOne e1 then e2
  else if is_one e2 then e1
  else if (e_cmp e1 e2)<0 then f(e1,e2,loc) else f(e2,e1,loc)


(* normalize add/sub expression *)
let rec simp_addsub e1 e2 loc =
  let (lhs,rhs)=norm_two_sides e1 e2 in
  match rhs with
  | IConst(0,_) -> lhs
  | _ -> Subtract(lhs,rhs,loc)

(* normalise and simplify expression *)
(* add to take a v->c eq_map *)
(* and norm_exp_aux (e:exp) = match e with  *)

and norm_exp (e:exp) = 
  (* let () = print_string "\n !!!!!!!!!!!!!!!! norm exp aux \n" in *)
  let rec helper e = match e with
    | Var _ 
    | Null _ | IConst _ | InfConst _ | NegInfConst _ | FConst _ | AConst _ | Tsconst _ 
    | Bptriple _
    | Level _ -> e
    | Tup2 ((e1,e2),l) -> Tup2 ((helper e1,helper e2),l) 
    | Add (e1,e2,l) -> simp_addsub e (IConst(0,no_pos)) l 
    | Subtract (e1,e2,l) -> simp_addsub e1 e2 l 
    | Mult (e1,e2,l) -> 
      let e1=helper e1 in 
      let e2=helper e2 in
      if (is_zero_int e1 || is_zero_int e2) then IConst(0,l)
      else if (is_zero_float e1 || is_zero_float e2) then FConst(0.0,l)
      else two_args (helper e1) (helper e2) is_one (fun x -> Mult x) l
    | Div (e1,e2,l) -> if is_one e2 then e1 else Div (helper e1,helper e2,l)
    | Max (e1,e2,l)-> two_args (helper e1) (helper e2) (fun _ -> false) (fun x -> Max x) l
    | Min (e1,e2,l) -> two_args (helper e1) (helper e2) (fun _ -> false) (fun x -> Min x) l
    | TypeCast (ty, e1, l) -> TypeCast (ty, helper e1, l)
    | Bag (e,l)-> Bag ( List.sort e_cmp (List.map helper e), l)    
    | BagUnion (e,l)-> BagUnion ( List.sort e_cmp (List.map helper e), l)    
    | BagIntersect (e,l)-> BagIntersect ( List.sort e_cmp (List.map helper e), l)    
    | BagDiff (e1,e2,l) -> BagDiff (helper e1, helper e2, l)
    | List (e,l)-> List (List.sort e_cmp (List.map helper e), l)    
    | ListCons (e1,e2,l)-> ListCons(helper e1, helper e2,l)      
    | ListHead (e,l)-> ListHead(helper e, l)      
    | ListTail (e,l)-> ListTail(helper e, l)      
    | ListLength (e,l)-> ListLength(helper e, l)
    | ListAppend (e,l) -> ListAppend ( List.sort e_cmp (List.map helper e), l)    
    | ListReverse (e,l)-> ListReverse(helper e, l) 
    | ArrayAt (a, i, l) -> ArrayAt (a, List.map helper i, l) (* An Hoa *) 
    | Func (id, es, l) -> Func (id, List.map helper es, l)
    | Template t -> Template { t with 
                               templ_args = List.map helper t.templ_args; 
                               templ_body = map_opt helper t.templ_body; }
  in helper e

(* if v->c, replace v by the constant whenever encountered 
   normalise each sub-expresion only once please.
*)
(* normalise add/subtract on both lhs (e1) and rhs (e2) *)
and norm_two_sides (e1:exp) (e2:exp)   =
  let rec help_add e s pa sa c  = match e with
    | Subtract (e1,e2,l) -> help_add e1 (Add(e2,s,l)) pa sa c
    | IConst(i,_)  -> help_sub s pa sa (c+i) 
    | Add (Add(e1,e2,l1),e3,l2) -> help_add (Add(e1,Add(e2,e3,no_pos),l2)) s pa sa c
    | Add (IConst(i,l1),e,l2) -> help_add e s pa sa (c+i) 
    | Add (Subtract(e1,e2,l1),e3,l2) -> help_add (Add(e1,e3,l2)) (Add(e2,s,no_pos)) pa sa c
    | Add (e1,e2,l1) -> help_add e2 s (e1::pa) sa c (* normalise e1, is e1=c? *)
    | e1 -> help_sub s (e1::pa) sa c (* normalise e1, is e1=c? *)
  and help_sub e pa sa c  = match e with
    | IConst(i,_)  -> (pa, sa,c-i)
    | Subtract (e1,e2,l)  -> help_add e2 e1 pa sa c
    | Add (Add(e1,e2,l1),e3,l2) -> help_sub (Add(e1,Add(e2,e3,no_pos),l2)) pa sa c
    | Add (IConst(i,l1),e,l2) -> help_sub e pa sa (c-i) 
    | Add (Subtract(e1,e2,l1),e3,l2) -> help_add e2 (Add(e1,e3,l2))  pa sa c
    | Add (e1,e2,l1) -> help_sub e2 pa (e1::sa) c (* normalise e1, is e1=c? *)
    | e1 -> (pa, e1::sa, c) in (* normalise e1, is e1=c? *)
  let (lhs,rhs,i) = help_add e1 e2 [] [] 0 in
  (* let (lhs,rhs) = (List.map norm_exp lhs, List.map norm_exp rhs) in *)
  if (lhs==[]) then (IConst(i,no_pos),addlist_to_exp rhs)
  else if (rhs==[]) then  (addlist_to_exp lhs, IConst(-i,no_pos))
  else if (i==0) then (addlist_to_exp lhs, addlist_to_exp rhs)
  else if (simple rhs) then (Add(IConst(i,no_pos),addlist_to_exp lhs,no_pos),addlist_to_exp rhs)
  else (addlist_to_exp lhs, Add(IConst(-i,no_pos),addlist_to_exp rhs,no_pos))

let norm_bform_leq (e1:exp)  (e2:exp) loc : p_formula = 
  let (lhs,rhs) = norm_two_sides e1 e2 in
  Lte(lhs,rhs,loc)

let norm_bform_eq (e1:exp)  (e2:exp) loc : p_formula = 
  let (lhs,rhs) = norm_two_sides e1 e2 in
  Eq(lhs,rhs,loc)

let norm_bform_neq (e1:exp)  (e2:exp) loc : p_formula = 
  let (lhs,rhs) = norm_two_sides e1 e2 in
  Neq(lhs,rhs,loc)

let simp_bform simp bf =
  let f_b e = None in
  let f_e e = match e with
    | Var _ -> Some (simp e)
    | _ -> None in
  transform_b_formula (f_b,f_e) bf

(*Called directly from mcpure.ml*)
(* normalise and simplify b_formula *)
let norm_bform_a (bf:b_formula) : b_formula =
  if (not !Globals.allow_norm) then bf else
    (*let bf = x_add_1 b_form_simplify bf in *)
    let fvars = bfv bf in
    let contain_waitlevel = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) fvars in
    if (contain_waitlevel || (is_float_bformula bf)) then bf
    else
      let (pf,il) = bf in	
      let npf = let rec helper pf =
                  match pf with 
                  | Lt  (e1,e2,l) -> if contains_inf e1 || contains_inf e2 then pf else
                      norm_bform_leq (Add(e1,IConst(1,no_pos),l)) e2 l
                  | Lte (e1,e2,l) -> norm_bform_leq e1 e2 l
                  | Gt  (e1,e2,l) ->  if contains_inf e1 || contains_inf e2 then pf else
                      norm_bform_leq (Add(e2,IConst(1,no_pos),l)) e1 l
                  | Gte (e1,e2,l) ->  norm_bform_leq e2 e1 l
                  | Eq  (e1,e2,l) -> norm_bform_eq e1 e2 l
                  | Neq (e1,e2,l) -> norm_bform_neq e1 e2 l 
                  | BagIn (v,e,l) -> BagIn (v, norm_exp e, l)
                  | BagNotIn (v,e,l) -> BagNotIn (v, norm_exp e, l)
                  | ListIn (e1,e2,l) -> ListIn (norm_exp e1,norm_exp e2,l)
                  | ListNotIn (e1,e2,l) -> ListNotIn (norm_exp e1,norm_exp e2,l)
                  | Frm _ | BConst _ | BVar _ | EqMax _  | XPure _ 
                  | EqMin _ |  BagSub _ | BagMin _ 
                  | BagMax _ | ListAllN _ | ListPerm _ | SubAnn _ -> pf
                  (* | VarPerm _ -> pf *)
                  | RelForm (id,exs,l) -> 
                    let exs = List.map norm_exp exs in
                    RelForm (id,exs,l)
                  | ImmRel (r, cond,l) -> ImmRel (helper r, cond,l)
                  | LexVar t_info -> 
                    let nle = List.map norm_exp t_info.lex_exp in
                    let nlt = List.map norm_exp t_info.lex_tmp in
                    LexVar { t_info with lex_exp = nle; lex_tmp = nlt; }
        in helper pf
      in (npf, il)

let norm_exp b =
  let pr = !print_exp in
  Debug.no_1 "CP.norm_exp" pr pr norm_exp b

let norm_bform_aux (bf:b_formula) : b_formula = norm_bform_a bf

let norm_bform_opt bf =
  let (pf,_) = bf in
  match pf with
  | BConst _ | XPure _ | BVar _ | EqMax _ 
  | EqMin _ |  BagSub _ | BagMin _ 
  | BagMax _ | ListAllN _ | ListPerm _ -> None 
  | _ -> Some bf 

let norm_bform_option (bf:b_formula) =
  let bf=norm_bform_aux bf in
  norm_bform_opt bf


let norm_bform_option_debug (bf:b_formula) : b_formula option =
  let r = norm_bform_aux bf in
  let () = print_string ("norm_bform inp :"^(!print_b_formula bf)^"\n") in
  let () = print_string ("norm_bform out :"^(!print_b_formula r)^"\n") in
  norm_bform_opt r


let arith_simplify_new (pf : formula) :  formula =
  if (not !Globals.allow_norm) then pf else
    let rec helper pf = match pf with
      |  BForm (b,lbl) -> BForm (norm_bform_aux b,lbl)
      |  And (f1, f2, loc) -> And (helper f1, helper f2, loc)
      |  AndList b -> AndList (map_l_snd helper b)
      |  Or (f1, f2, lbl, loc) -> Or (helper f1, helper f2, lbl, loc)
      |  Not (f1, lbl, loc) ->  Not (helper f1, lbl, loc)
      |  Forall (v, f1, lbl, loc) ->  Forall (v, helper f1, lbl, loc)
      |  Exists (v, f1, lbl, loc) ->  Exists (v, helper f1, lbl, loc)
    in helper pf

(* get string name of var e *)
let string_of_var_eset e : string =
  EMapSV.string_of e


let get_sub_debug s n m =
  let () = print_string ("get_sub inp:"^s^";"^(string_of_int n)^";"^(string_of_int m)^"\n") in
  let r = String.sub s n m in
  let () = print_string ("get_sub out:"^r^"\n") in
  r

(* get args from a bform formula *)
let get_bform_eq_args_aux conv (bf:b_formula) =
  let (pf,_) = bf in
  match pf with
  | Eq(e1,e2,_) -> 
    let ne1=conv e1 in 
    let ne2=conv e2 in
    (match ne1,ne2 with
     | Var(v1,_),Var(v2,_) -> Some (v1,v2)
     | _, _ -> None)
  | _-> None     

let get_bform_neq_args_aux conv (bf:b_formula) =
  let (pf,_) = bf in
  match pf with
  | Neq(e1,e2,_) -> 
    let ne1=conv e1 in 
    let ne2=conv e2 in
    (match ne1,ne2 with
     | Var(v1,_),Var(v2,_) -> Some (v1,v2)
     | _, _ -> None)
  | _-> None     	  

(* get arguments of an eq formula *)
let get_bform_eq_args (bf:b_formula) =
  get_bform_eq_args_aux (fun x -> x) bf

let mk_sp_const (i:int) = 
  let n= const_prefix^(string_of_int i)
  in SpecVar ((Int), n , Unprimed) 

let mk_sv_aconst (a:heap_ann) =
  let ann = imm_const_prefix^(string_of_heap_ann a)
  in SpecVar ((AnnT), ann , Unprimed)

let conv_exp_to_var (e:exp) : (spec_var * loc) option = 
  match e with
  | IConst(i,loc) -> Some (mk_sp_const i,loc)
  | Null loc -> Some (null_var,loc)
  | Var (sv,p) -> Some (sv,p)
  | _ -> None

let conv_ann_exp_to_var (e:exp) : (spec_var * loc) option = 
  match e with
  | AConst(a,loc) -> Some (mkAnnSVar a,loc)
  | Var(v,loc)    -> Some (v, loc)
  | _ -> None

(* convert exp to var representation where possible *)
let conv_exp_with_const e = match conv_exp_to_var e with
  | Some (v,loc) -> Var(v,loc)
  | _ -> e

let imm_to_spec_var ann = 
  match ann with
  | ConstAnn a  -> mkAnnSVar a
  | PolyAnn  sv -> sv
  | _ -> failwith 
        ("imm_to_spec_var do do not provide support for nested TempAnn/TempRes"^(string_of_imm ann))

let imm_to_spec_var_opt ann = 
  match ann with 
  | PolyAnn ann  -> Some ann
  | ConstAnn ann -> Some (mkAnnSVar ann)
  | _ -> None 

let imm_to_sv_list ann = 
  List.fold_left (fun acc a -> match a with
      | Some ann -> acc@ann 
      | None     -> acc) [] ann

let imm_to_exp ann loc = 
  match ann with
  | ConstAnn a  -> AConst(a, loc)
  | PolyAnn  sv -> Var(sv, loc)
  | _ -> failwith "Cpure.ml currently we do not provide support for TempAnn/TempRes exp"

let exp_to_imm (e:exp) : ann = 
  match e with
  | AConst(a,loc) -> ConstAnn a
  | Var(v,loc)    -> PolyAnn v
  | _ -> NoAnn

let mkSubAnn_from_imm ?pos1:(loc1=no_pos) ?pos2:(loc2=no_pos) a1  a2 = mkSubAnn (imm_to_exp a1 loc1) (imm_to_exp a2 loc2)

(* get arguments of bformula and allowing constants *)
let get_bform_eq_args_with_const (bf:b_formula) =
  get_bform_eq_args_aux conv_exp_with_const bf

let get_bform_eq_args_with_const_debug (bf:b_formula) =
  Debug.no_1 " get_bform_eq_args_with_const" (!print_b_formula) (fun _ -> "?") get_bform_eq_args_with_const bf

let get_bform_neq_args_with_const (bf:b_formula) =
  get_bform_neq_args_aux conv_exp_with_const bf

(* form bformula assuming only vars *)
let form_bform_eq (v1:spec_var) (v2:spec_var) =
  let conv v = Var(v,no_pos) in
  if ((is_const v1) || (is_const v2)) then              
    Error.report_error  {
      Error.error_loc = no_pos;
      Error.error_text =  "form_bform_eq : adding an equality with a constant"; }
  else Eq(conv v1,conv v2,no_pos)

(* form bformula allowing constants to be converted *)
let form_bform_eq_with_const (v1:spec_var) (v2:spec_var) =
  let conv v = conv_var_to_exp v
  in Eq(conv v1,conv v2,no_pos)

(* form an equality formula assuming vars only *)
let form_formula_eq (v1:spec_var) (v2:spec_var) =
  BForm (((form_bform_eq v1 v2), None), None)

(* form an equality formula and allowing constants *)
let form_formula_eq_with_const (v1:spec_var) (v2:spec_var) : formula =
  BForm (((form_bform_eq_with_const v1 v2), None), None)

(* get args of a equality formula *)
let get_bform_eq_args_debug (bf:b_formula) : (spec_var * spec_var) option =
  let s="get_bform_eq_args " in
  let s="DEBUG "^s in
  let r=get_bform_eq_args bf in
  let () = print_string (s^"inp:"^(!print_b_formula bf)^"\n") in
  let () = match r with 
    | Some (v1,v2) -> let o=form_bform_eq v1 v2 in
      print_string (s^"out:"^(!print_p_formula o)^"\n") 
    | None ->  print_string (s^"out: None \n")
  in r

(* no constant must be added when adding equiv *)
let add_equiv_eq a v1 v2 = 
  if (is_const v1)||(is_const v2) then
    Error.report_error  {
      Error.error_loc = no_pos;
      Error.error_text =  "add_equiv_eq bug : adding an equality with a constant"; }
  else EMapSV.add_equiv a v1 v2

let add_equiv_eq_debug a v1 v2 = 
  let () = print_string ("add_equiv_eq inp1 :"^(string_of_var_eset a)^"\n") in
  let () = print_string ("add_equiv_eq inp2 :"^(full_name_of_spec_var v1)^","^(name_of_spec_var v2)^"\n") in
  let ax = add_equiv_eq a v1 v2 in
  let () = print_string ("add_equiv_eq out :"^(string_of_var_eset ax)^"\n") in
  ax

let add_equiv_list_eqs a evars =
  List.fold_left (fun tpl (sv1,sv2) -> add_equiv_eq tpl sv1 sv2) a evars

let find_eq_closure a svl =
  if EMapSV.is_empty a then svl else
    let eqc_svl = List.fold_left (fun r sv ->
        let eq_svl = EMapSV.find_equiv_all sv a in
        r@eq_svl
      ) svl svl
    in
    remove_dups_svl eqc_svl

(* constant may be added to map*)
let add_equiv_eq_with_const a v1 v2 = EMapSV.add_equiv a v1 v2

let add_equiv_eq_with_const_debug a v1 v2 = 
  let () = print_string ("add_equiv_eq_with_const inp1 :"^(string_of_var_eset a)^"\n") in
  let () = print_string ("add_equiv_eq_with_const inp2 :"^(full_name_of_spec_var v1)^","^(name_of_spec_var v2)^"\n") in
  let ax = add_equiv_eq_with_const a v1 v2 in
  let () = print_string ("add_equiv_eq_with_const out :"^(string_of_var_eset ax)^"\n") in
  ax

(* get arguments of an equality formula *)
let get_formula_eq_args (f:formula) =
  match f with
  | BForm(bf,_) -> get_bform_eq_args bf
  | _ -> None

let get_formula_eq_args_debug_add bf =
  let _=print_string ("Adding") in
  get_bform_eq_args_debug bf

let get_formula_eq_args_debug_chk bf =
  let _=print_string ("Checking") in
  get_bform_eq_args_debug bf

(* get var elements from a eq-map but remove constants *)
let get_elems_eq aset =
  let vl=EMapSV.get_elems aset in
  List.filter (fun v -> not(is_const v)) vl

(* get var elements from a eq-map allowing constants *)
let get_elems_eq_with_const aset =
  let vl=EMapSV.get_elems aset in
  List.filter (fun v -> true) vl

(* let get_elems_eq_with_const_debug aset = *)
(*   Debug.no_1_list "get_elems_eq_with_const" (string_of_var_eset) (full_name_of_spec_var) get_elems_eq_with_const aset *)

(* get var elements from a eq-map allowing null *)
let get_elems_eq_with_null aset =
  let vl=EMapSV.get_elems aset in
  List.filter (fun v -> not(is_int_const v)) vl

(* below is for Andreea to implement,
   likely to require Util

*)

(* creates a false aset*)
let mkFalse_var_aset = add_equiv_eq_with_const EMapSV.mkEmpty  (mk_sp_const 0) (mk_sp_const 3)

(*****)	
let get_bform_eq_vars (bf:b_formula) : (spec_var * spec_var) option =
  let (pf,_) = bf in
  match pf with
  | Eq(Var(v1,_),Var(v2,_),_) -> Some (v1,v2)
  | _ -> None

(* normalise eq_map - to implement*)
(* remove duplicate occurrences of a var in a partition, 
   check singleton & remove
   check false by presence of duplicate constants --> change to 1=0

   @return: var_aset - normalized eq
   			 bool(1) - flag that tells if the eq has changed
   			 bool(2) - flag that tells if there is a conflict in the eq
*)

let normalise_eq_aux ( aset : var_aset) : var_aset * bool * bool= 
  let plst = EMapSV.partition aset in
  let (nlst,flag) = List.fold_left 
      (fun (rl,f) l -> 
         let nl=remove_dups_svl l in
         (nl::rl,(f||not((List.length nl)==(List.length l))))) 
      ([],false) plst in
  let (nlst2,flag2) = List.fold_left 
      (fun (rl,f) ls -> 
         if (List.length ls<=1) then (rl,true)
         else (ls::rl,f))
      ([],flag) nlst in
  let is_conflict = List.fold_left 
      (fun f ls -> 
         (f || (let cl= List.filter (fun v -> is_const v) ls in (List.length cl)>1)))
      false nlst2 
  in
  if is_conflict then (mkFalse_var_aset, true, true)
  else
    ((EMapSV.un_partition nlst2),flag2, false)


(* return the normalized eq *)
let normalise_eq (aset : var_aset) : var_aset = 
  let (r, _, _) = normalise_eq_aux aset in r

(* print if there was a change in state check - *)
let normalise_eq_debug (aset : var_aset) : EMapSV.emap =
  let ax, change, _ = normalise_eq_aux aset in
  (if change then
     let () = print_string ("normalise_eq inp :"^(string_of_var_eset aset)^"\n") in
     print_string ("partition_eq out :"^(string_of_var_eset ax)^"\n"));
  (ax)

(* check if an eq_map has a contradiction - to implement *)
(* call normalised_eq and check if equal to 1=0 *)
(* @return: bool - flag that tells if there is a conflict in the eq 
   			var_aset - normalized eq *)
let is_false_and_normalise_eq (aset : var_aset) : bool * var_aset =
  let (ax, _, conflict) = normalise_eq_aux aset in (conflict, ax) 

(* print if false detected - when debugging *)
let is_false_and_normalise_eq_debug (aset : var_aset) : bool * var_aset = 
  let (ax, _, conflict) = normalise_eq_aux aset in
  let () = print_string ("normalise_eq inp :"^(string_of_var_eset aset) ^ "\n") in
  let () = print_string ("partition_eq out :"^(string_of_var_eset ax) ^ "\n") in
  let () = print_string ("conflict in eq: " ^ (string_of_bool conflict) ^ "\n") in
  (conflict, ax)

(* check if an eq_map has a contradiction*)
(* call normalised_eq and check if equal to 1=0 *)
let is_false_eq (aset : var_aset) : bool = 
  let (_, _, conflict) = normalise_eq_aux aset in conflict

(* check if v is a constant*)
(* return a list with all constant having the same key as v*)
let get_all_const_eq (aset : var_aset) (v : spec_var) : spec_var list =
  let nlst = EMapSV.find_equiv_all v aset in
  List.filter (is_const) nlst

(* check if v is an int constant and return its value, if so - to implement *)
(* use get_var_const *)
(* return i if i_const found *)
(* report error if wrong type found *)
let conv_var_to_exp_eq (aset : var_aset) (v:spec_var) : exp = 
  let nlst = get_all_const_eq aset v in
  match nlst with
  | [] -> Var(v,no_pos)
  | hd::_ -> conv_var_to_exp hd

(*Convert an expresion to another expresion after replacing the variables representing constants*)
let conv_exp_to_exp_eq aset e : exp =
  match e with
  | Var(v,_) -> let r = conv_var_to_exp_eq aset v in
    if not(r==e) then ((Gen.Profiling.add_to_counter "var_changed_2_const" 1); r)
    else r
  | _ -> e

(* check if v is null - to implement *)
let is_null_var_eq (aset : var_aset) (v:spec_var) : bool = 
  let nlst = get_all_const_eq aset v in
  List.exists (is_null_const) nlst


let string_of_var_list l : string =
  Gen.BList.string_of_f name_of_spec_var l

let string_of_p_var_list l : string =
  Gen.BList.string_of_f (fun (v1,v2) -> "("^(full_name_of_spec_var v1)^","^(full_name_of_spec_var v2)^")") l

(* get two lists - no_const & with_const *)
let get_equiv_eq_split aset =
  let vl=EMapSV.get_equiv aset in
  List.partition (fun (v1,v2) -> not(is_const v1) && not(is_const v2) ) vl

(* get eq pairs without const *)
let get_equiv_eq_no_const aset =
  let vl=EMapSV.get_equiv aset in
  List.filter (fun (v1,v2) -> not(is_const v1) && not(is_const v2) ) vl

(* get all eq pairs *)
let get_equiv_eq_all aset =
  let vl=EMapSV.get_equiv aset in vl

(* get eq pairs without const *)
let get_equiv_eq aset = get_equiv_eq_no_const  aset

(* get eq pairs without int const *)
let get_equiv_eq_with_null aset =
  let vl=EMapSV.get_equiv aset in
  List.filter (fun (v1,v2) -> not(is_int_const v1) && not(is_int_const v2) ) vl

(* get eq pairs without int const *)
let get_equiv_eq_with_const aset =
  let vl=EMapSV.get_equiv aset in
  List.filter (fun (v1,v2) -> true ) vl

let get_equiv_eq_with_const_debug aset =
  let ax = get_equiv_eq_with_const aset in
  let () = print_string ("get_equiv_eq_with_const inp :"^(string_of_var_eset aset)^"\n") in
  let () = print_string ("get_equiv_eq_with_const out :"^(string_of_p_var_list ax)^"\n") in
  ax

(*
(* return constant int for e *)
let find_int_const_eq2  (eq:'a->'a->bool) (str:'a->string) (e:'a) (s:'a e_set) : int option  =
  let r1 = find_eq2 eq s e in
  if (r1==[]) then None
  else let ls = List.filter (fun (a,k) -> k==r1 && (is_int_const (str a))  ) s in
  match ls with
    | [] -> None 
    | (x,_)::_ -> get_int_const x

*)


let is_leq eq e1 e2 =
  match e1,e2 with
  | IConst (i1,_), IConst(i2,_) -> i1<=i2
  | AConst (i1,_), AConst(i2,_) 
    -> (int_of_heap_ann i1)<=(int_of_heap_ann i2)
  | _,_ -> eqExp_f eq e1 e2

let is_lt eq e1 e2 =
  match e1,e2 with
  | IConst (i1,_), IConst(i2,_) -> i1<i2
  | AConst (i1,_), AConst(i2,_) 
    -> (int_of_heap_ann i1)<(int_of_heap_ann i2)
  | _,_ -> false

let is_gt eq e1 e2 =
  match e1,e2 with
  | IConst (i1,_), IConst(i2,_) -> i1>i2
  | AConst (i1,_), AConst(i2,_) 
    -> (int_of_heap_ann i1)>(int_of_heap_ann i2)
  | _,_ -> false

(*ann  expressions *)
let const_ann_lend = AConst (Lend,no_pos)
let const_ann_imm = AConst (Imm,no_pos)
let const_ann_mut = AConst (Mutable,no_pos)
let const_ann_abs = AConst (Accs,no_pos)
let const_ann_top = AConst (imm_top, no_pos)
let const_ann_bot = AConst (imm_bot, no_pos)
(*annotations *)
let imm_ann_top = ConstAnn imm_top
let imm_ann_bot = ConstAnn imm_bot

let is_diff e1 e2 =
  match e1,e2 with
  | IConst (i1,_), IConst(i2,_) -> i1<>i2
  | AConst (i1,_), AConst(i2,_) 
    -> (int_of_heap_ann i1)<>(int_of_heap_ann i2)
  | Tsconst (t1,_), Tsconst (t2,_) -> not (Tree_shares.Ts.eq t1 t2)
  | _,_ -> false

(* lhs |- e1<=e2 *)
let check_imply_leq eq lhs e1 e2 =
  let rec helper l = match l with
    | [] -> -1
    | a::ls -> if helper2 a then 1 else helper ls
  and helper2 a = match a with
    | Eq(d1,d2,_) ->          
      if eqExp_f eq d1 e1 then is_leq eq d2 e2 
      else if eqExp_f eq d2 e2 then is_leq eq e1 d1 
      else helper2 (Lte(d2,d1,no_pos))
    | Lte(d1,d2,_) -> 
      if eqExp_f eq d1 e1 then is_leq eq d2 e2 
      else if eqExp_f eq d2 e2 then is_leq eq e1 d1 
      else false
    | _ -> false
  in helper lhs

(* lhs |- e1=e2 *)
let check_imply_eq eq lhs e1 e2 = 
  let rec helper l = match l with
    | [] -> -1
    | a::ls -> if helper2 a then 1 else helper ls
  and helper2 a = match a with
    | Eq(d1,d2,_) ->          
      (eqExp_f eq d1 e1 && eqExp_f eq d2 e2) ||
      (eqExp_f eq d1 e2 && eqExp_f eq d2 e1)
    | _ -> false
  in if ((eqExp_f eq) e1 e2) then 1
  else helper lhs 

(* TODO: SubAnn may not be properly implemented here! *)

(* lhs |- e1!=e2 *)
let check_imply_neq eq lhs e1 e2 = 
  let rec helper l = match l with
    | [] -> -1
    | a::ls -> if helper2 a then 1 else helper ls
  and helper2 a = match a with
    | Eq(d1,d2,_) ->          
      if eqExp_f eq d1 e1 then (is_lt eq d2 e2) || (is_lt eq e2 d2)
      else if eqExp_f eq d2 e2 then (is_lt eq e1 d1) || (is_lt eq d1 e1)
      else helper2 (Lte(d2,d1,no_pos))
    (*((eqExp_f eq d1 e1) && (is_diff d2 e2)) || ((eqExp_f eq d2 e2) && (is_diff e1 d1)) ||
      ((eqExp_f eq d2 e1) && (is_diff d1 e2)) || ((eqExp_f eq d1 e2) && (is_diff e1 d2)) ||
      (helper2 (Lte(d2,d1,no_pos)))*)
    | Lte(d1,d2,_) -> 
      if eqExp_f eq d1 e1 then is_lt eq d2 e2 
      else if eqExp_f eq d2 e2 then is_lt eq e1 d1 
      else if eqExp_f eq d1 e2 then is_lt eq d2 e1 
      else if eqExp_f eq d2 e1 then is_lt eq e2 d1 
      else 
        false
    | _ -> false
  in if ((eqExp_f eq) e1 e2) then -2
  else helper lhs 

(* type: (spec_var -> spec_var -> bool) -> p_formula list -> exp -> exp -> int *)

let check_imply_neq_debug eq lhs e1 e2 = 
  Debug.no_3 
    "check_imply_neq" 
    (fun c-> String.concat "&" (List.map !print_p_formula c))
    !print_exp 
    !print_exp 
    string_of_int (check_imply_neq eq ) lhs e1 e2

let check_eq_bform eq lhs rhs failval = 
  if List.exists (equalBFormula_f eq rhs) lhs then 1
  else failval

(* assume b_formula has been normalized 
     1 - true
     0 - dont know
     -1 - likely false
    -2 - definitely false
*)
(* TODO: Can slicing be applied here? *)
let fast_imply (aset: var_aset) (lhs: b_formula list) (rhs: b_formula) : int =
  (*normalize lhs and rhs*)
  let simp e = conv_exp_to_exp_eq aset e in
  let normsimp lhs rhs =
    let () = Gen.Profiling.push_time "fi-normsimp" in
    let lhs = List.map (fun e -> norm_bform_a(simp_bform simp e)) lhs in
    let rhs = norm_bform_a( simp_bform simp rhs) in
    let () = Gen.Profiling.pop_time "fi-normsimp" in
    (lhs,rhs) in
  let lhs,rhs = if !Globals.enable_norm_simp then normsimp lhs rhs 
    else (lhs,rhs)
  in
  let r = 
    let eq x y = EMapSV.is_equiv aset x y in
    let r1=check_eq_bform eq lhs rhs 0 in
    if (r1>0) then r1
    else
      let plhs = List.map (fun (pf,_) -> pf) lhs in
      let (prhs,_) = rhs in
      match prhs with
      | BConst(true,_) -> 1
      | SubAnn(e1,e2,_) -> check_imply_leq eq plhs e1 e2
      | Lte(e1,e2,_) -> check_imply_leq eq plhs e1 e2
      | Eq(e1,e2,_) -> check_imply_eq eq plhs e1 e2
      | Neq(e1,e2,_) -> check_imply_neq eq plhs e1 e2
      | EqMin _ | EqMax _ (* min/max *) -> 0
      | Lt _ | Gt _ | Gte _ -> (* RHS not normalised *) 
        let () = print_string "warning fast_imply : not normalised"
        in 0
      | _ -> (* use just syntactic checking *) 0 in
  let () = if r>0 then (Gen.Profiling.add_to_counter "fast_imply_success" 1) else () in
  (* let _  = Gen.Profiling.pop_time "fast_imply" in *) r

let fast_imply a l r = Gen.Profiling.do_3 "fast_imply" fast_imply a l r

let fast_imply aset (lhs:b_formula list) (rhs:b_formula) : int =
  let pr1 = !print_b_formula in
  Debug.no_2 "fast_imply" (pr_list pr1) pr1 string_of_int (fun _ _ -> fast_imply aset lhs rhs) lhs rhs


let rec replace_pure_formula_label nl f = match f with
  | BForm (bf,_) -> BForm (bf,(nl()))
  | And (b1,b2,b3) -> And ((replace_pure_formula_label nl b1),(replace_pure_formula_label nl b2),b3)
  | AndList b -> AndList (map_l_snd (replace_pure_formula_label nl) b)
  | Or (b1,b2,b3,b4) -> Or ((replace_pure_formula_label nl b1),(replace_pure_formula_label nl b2),(nl()),b4)
  | Not (b1,b2,b3) -> Not ((replace_pure_formula_label nl b1),(nl()),b3)
  | Forall (b1,b2,b3,b4) -> Forall (b1,(replace_pure_formula_label nl b2),(nl()),b4)
  | Exists (b1,b2,b3,b4) -> Exists (b1,(replace_pure_formula_label nl b2),(nl()),b4)

let store_tp_is_sat : (formula -> bool) ref = ref (fun _ -> true)

let tp_is_sat = store_tp_is_sat

let rec imply_disj_orig_x ante_disj conseq t_imply imp_no =
  x_dinfo_hp (add_str "ante: " (pr_list !print_formula)) ante_disj no_pos;
  x_dinfo_hp (add_str "coseq : " ( !print_formula)) conseq no_pos;
  match ante_disj with
  | h :: rest ->
    x_dinfo_hp (add_str "h : " ( !print_formula)) h no_pos;
    let r1,r2,r3 = (t_imply h conseq (string_of_int !imp_no) true None) in
    x_dinfo_hp (add_str "res : " (string_of_bool)) r1 no_pos;
    if r1 then
      let r1,r22,r23 = (imply_disj_orig_x rest conseq t_imply imp_no) in
      (r1,r2@r22,r23)
    else (r1,r2,r3)
  | [] -> (true,[],None)

and imply_disj_orig_x0 ante_disj conseq t_imply imp_no =
  let i = List.length ante_disj in
  if (i > 1) 
  then 
    begin
      let pr = !print_formula in
      (* perform unsat checking if i>1 *)
      let f = !store_tp_is_sat in
      (* removing unsatisfiable LHS disjunct *)
      let (ante_disj,false_st) = List.partition f ante_disj in
      let i = List.length false_st in
      let j = List.length ante_disj in
      let () = 
        if (i>0) 
        then
          let pri = string_of_int in
          let () = x_tinfo_hp (add_str "(unsat ante, sat ante)" (pr_pair pri pri)) (i,j) no_pos in
          x_tinfo_hp (add_str "unsat ante removed" (pr_list pr)) false_st no_pos
        else () 
      in 
      (* disable assumption filtering if ante_disj>1 *)
      (* wrap_no_filtering (imply_disj_orig_x ante_disj conseq t_imply) imp_no *)
      (imply_disj_orig_x ante_disj conseq t_imply) imp_no
    end
  else imply_disj_orig_x ante_disj conseq t_imply imp_no

and imply_disj_orig ante_disj conseq t_imply imp_no =
  let pr = !print_formula in
  Debug.no_2 "imply_disj_orig" (pr_list pr) pr (fun (b,_,_) -> string_of_bool b)
    (fun ante_disj conseq -> imply_disj_orig_x0 ante_disj conseq t_imply imp_no) ante_disj conseq

let rec imply_one_conj_orig one_ante_only ante_disj0 ante_disj1 conseq t_imply imp_no =
  let xp01,xp02,xp03 = x_add imply_disj_orig ante_disj0 conseq t_imply imp_no in
  if not(xp01) && !Globals.super_smart_xpure && not(one_ante_only) then
    let () = x_dinfo_pp ("\nSplitting the antecedent for xpure1:\n") no_pos in
    let (xp11,xp12,xp13) = x_add imply_disj_orig ante_disj1 conseq t_imply imp_no in
    let () = x_dinfo_pp ("\nDone splitting the antecedent for xpure1:\n") no_pos in
    (xp11,xp12,xp13)
  else (xp01,xp02,xp03)

let imply_one_conj_orig one_ante_only ante_disj0 ante_disj1 conseq t_imply imp_no =
  let pr = !print_formula in
  Debug.no_3 "imply_one_conj_orig" (pr_list pr) (pr_list pr) pr (fun (b,_,_) -> string_of_bool b)
    (fun _ _ _ -> imply_one_conj_orig one_ante_only ante_disj0 ante_disj1 conseq t_imply imp_no) 
    ante_disj0 ante_disj1 conseq

let rec imply_conj_orig one_ante_only ante_disj0 ante_disj1 conseq_conj t_imply imp_no
  : bool * (Globals.formula_label option * Globals.formula_label option) list *
    Globals.formula_label option=
  let pr = pr_list !print_formula in
  Debug.no_3 "imply_conj_orig" pr pr pr (fun (b,_,_) -> string_of_bool b)
    (fun ante_disj0 ante_disj1 conseq_conj-> imply_conj_orig_x one_ante_only ante_disj0 ante_disj1 conseq_conj t_imply imp_no)
    ante_disj0 ante_disj1 conseq_conj

and imply_conj_orig_x one_ante_only ante_disj0 ante_disj1 conseq_conj t_imply imp_no
  : bool * (Globals.formula_label option * Globals.formula_label option) list *
    Globals.formula_label option=
  match conseq_conj with
  | h :: rest ->
    let (r1,r2,r3)=(imply_one_conj_orig one_ante_only ante_disj0 ante_disj1 h t_imply imp_no) in
    if r1 then
      let r1,r22,r23 = (imply_conj_orig_x one_ante_only ante_disj0 ante_disj1 rest t_imply imp_no) in
      (r1,r2@r22,r23)
    else (r1,r2,r3)
  | [] -> (true,[],None)
(*###############################################################################  incremental_testing*)
(*check implication having a single formula on the lhs and a conjuction of formulas on the rhs*)
(*let rec imply_conj (send_ante: bool) ante conseq_conj t_imply (increm_funct :(formula) Globals.incremMethodsType option) process imp_no =
  (* let () = print_string("\nCpure.ml: imply_conj") in *)
  match conseq_conj with
    | h :: rest ->
  	      let r1,r2,r3 = (t_imply ante h (string_of_int !imp_no) true ( Some (process, send_ante))) in
          (* let () = print_string("\nCpure.ml: h:: rest "^(string_of_bool r1)) in *)
          if r1 then
            let send_ante = if (!Globals.enable_incremental_proving) then false
            else send_ante in
  	        let r1,r22,r23 = (imply_conj send_ante ante rest t_imply increm_funct process imp_no) in
  	        (r1,r2@r22,r23)
  	      else (r1,r2,r3)
    | [] -> (* let () = print_string("\nCpure.ml: []")  in*) (true,[],None)

  let rec imply_disj_helper ante_disj conseq_conj t_imply (increm_funct: (formula) Globals.incremMethodsType option) process imp_no
      : bool * (Globals.formula_label option * Globals.formula_label option) list * Globals.formula_label option =
  match ante_disj with
    | h :: rest ->
          (* let () = print_string("\nCpure.ml: bef imply_conj ") in *)
  	      let (r1,r2,r3) = (imply_conj true(*<-send_ante*) h conseq_conj t_imply increm_funct process imp_no) in
          (* let () = print_string("\nCpure.ml: affer imply_conj " ^(string_of_bool r1)) in *)
  	      if r1 then
  	        let r1,r22,r23 = (imply_disj_helper rest conseq_conj t_imply increm_funct process imp_no) in
  	        (r1,r2@r22,r23)
  	      else (r1,r2,r3)
    | [] -> (true,[],None)

  let imply_disj ante_disj0 ante_disj1 conseq_conj t_imply (increm_funct: (formula) Globals.incremMethodsType option) imp_no
      : bool * (Globals.formula_label option * Globals.formula_label option) list * Globals.formula_label option =
  (* let () = print_string ("\nCpure.ml: CVC3 create process") in *)
  let start = ref false in
  let process = 
    match increm_funct with
      | Some ifun ->
            let proc0 = ifun#get_process() in 
            let proc = match proc0 with
              |Some pr -> pr
              |None -> (start :=true; ifun#start_p ()) in
            let () = ifun#push proc in
            Some proc
      | None -> None in
  let xp01,xp02,xp03 = imply_disj_helper ante_disj0 conseq_conj t_imply increm_funct process imp_no in
  let r = if ( not(xp01) ) then begin (*xpure0 fails to prove. try xpure1*)
    let () = x_dinfo_pp ("\nSplitting the antecedent for xpure1:\n") in
    let r1 = imply_disj_helper ante_disj1 conseq_conj t_imply increm_funct process imp_no in
    let () = x_dinfo_pp ("\nDone splitting the antecedent for xpure1:\n") in
    r1
  end else (xp01, xp02, xp03) in
  let _ =
    match (increm_funct, process, !start) with
      | (Some ifun, Some proc, true) -> ifun#stop_p proc
        (* let () = print_string("\nCpure.ml: stop process") in  *)
      | (_, _, _) -> () in
  (* let () = print_string ("\nCpure.ml: CVC3 stop process \n\n") in *)
  r*)

(*###############################################################################  *)

(* added for better normalization *)

type exp_form = 
  | C of int 
  | V of spec_var 
  | E of exp

type add_term = (int * exp_form)  
(* e.g i*e; special case of constant i*1  3*v  4*(a*b) *)

type mult_term = (exp_form * int) 
(* e^i; special case c^1 or c^-1*)

(* [2v,3,5v,6ab,..] *)
type add_term_list = add_term list (* default [] means 0 *)
type mult_term_list = mult_term list (* default [] means 1 *)

let mk_err s = Error.report_error
    { Error.error_loc = no_pos;
      Error.error_text = s } 

(* to be implemented : use GCD, then simplify fraction *)
let simp_frac c1 c2 = (c1,c2)

let gen_iconst (c1:int) (c2:int) : mult_term_list =
  let (d1,d2) = simp_frac c1 c2 in
  if (d1==1) then
    if (d2==1) then [] else [(C d2,-1)]
  else   
  if (d2==1) then [(C d1,1)] else [(C d1,1);(C d2,-1)]

let gen_var (v:spec_var) (c:int) : mult_term_list =
  if c==0 then [] else [(V v,c)]

let gen_exp (e:exp) (c:int) : mult_term_list =
  if c==0 then [] else [(E e,c)]

let mul_zero = [(C 0,1)]

let gen_add_exp (e:exp) (c:int) : add_term_list =
  if c==0 then [] else [(c,E e)]

let gen_add_var (e:spec_var) (c:int) : add_term_list =
  if c==0 then [] else [(c,V e)]

let gen_add_iconst (c:int) : add_term_list =
  if c==0 then [] else [(c,C 1)]

(* to be implemented *)
let eq_exp e1 e2 = false

let spec_var_cmp v1 v2 = String.compare (full_name_of_spec_var v1) (full_name_of_spec_var v2)

let cmp_term x y = match x,y with
  | C _, C _ -> 0
  | C _, _ -> -1
  | _ , C _ -> 1
  | V v1 , V v2 -> String.compare (full_name_of_spec_var v1) (full_name_of_spec_var v2)
  | V v , _ -> -1
  | _ , V v -> 1
  | E e1 , E e2 -> 0 (* to refine *)

let sort_add_term (xs:add_term_list) : add_term_list =
  let cmp (_,x) (_,y) = cmp_term x y
  in List.sort cmp xs

let cmp_mult_term (mt1: mult_term) (mt2: mult_term): int =
  let x, i1 = mt1 in
  let y, i2 = mt2 in
  let r = cmp_term x y in 
  if r == 0 then 
    compare i1 i2
  else r 

let sort_mult_term (xs:mult_term_list) : mult_term_list =
  List.sort cmp_mult_term xs

(* pre : c1!=0 *)
let rec norm_add_c (c1:int) (xs:add_term_list) : add_term_list =
  match xs with
  | [] -> gen_add_iconst c1
  | (i,C _)::xs -> norm_add_c (c1+i) xs
  | _ :: _ -> (gen_add_iconst c1)@norm_add xs

and norm_add_v c v (xs:add_term_list)  : add_term_list= 
  match xs with
  | [] -> gen_add_var v c
  | (i,V v1)::xs -> 
    if eq_spec_var v v1 then norm_add_v (i+c) v xs
    else (gen_add_var v c)@norm_add_v i v1 xs
  | _::_ -> (gen_add_var v c)@norm_add xs

and norm_add_e c e (xs:add_term_list) : add_term_list= 
  match xs with
  | [] -> gen_add_exp e c
  | (i,E e1)::xs -> 
    if eq_exp e e1 then norm_add_e (i+c) e xs
    else (gen_add_exp e c)@norm_add_e i e1  xs
  | _::_ -> (gen_add_exp e c)@norm_add xs

(* add_term_list --> add_term_list 
   2+3x+4x+4xy --> 2+7x+4xy
*)

and norm_add xs =
  match xs with 
  | [] -> []
  | (i,C _)::xs -> norm_add_c i xs
  | (i,V v)::xs -> norm_add_v i v xs
  | (i,E e)::xs -> norm_add_e i e xs

(* pre : c1!=0 *)
let rec norm_mult_c (c1:int) (c2:int) (xs:mult_term_list) : mult_term_list =
  match xs with
  | [] -> gen_iconst c1 c2
  | (C c,v)::xs -> 
    if c==0 then mul_zero else
    if v==1 then norm_mult_c (c*c1) c2 xs
    else norm_mult_c c1 (c2*c) xs
  | _ :: _ -> (gen_iconst c1 c2)@norm_mult xs

and norm_mult_v v c (xs:mult_term_list)  : mult_term_list= 
  match xs with
  | [] -> gen_var v c
  | (V v1,c1)::xs -> 
    if eq_spec_var v v1 then norm_mult_v v (c+c1) xs
    else (gen_var v c)@norm_mult_v v1 c1 xs
  | _::_ -> (gen_var v c)@norm_mult xs

and norm_mult_e e c (xs:mult_term_list) : mult_term_list= 
  match xs with
  | [] -> gen_exp e c
  | (E e1,c1)::xs -> 
    if eq_exp e e1 then norm_mult_e e (c+c1) xs
    else (gen_exp e c)@norm_mult_e e1 c1 xs
  | _::_ -> (gen_exp e c)@norm_mult xs

and norm_mult xs =
  match xs with 
  | [] -> []
  | (C c,b)::xs -> 
    if c==0 then mul_zero else
    if b==1 then norm_mult_c c 1 xs
    else norm_mult_c 1 c xs
  | (V v,p)::xs -> norm_mult_v v p xs
  | (E e,p)::xs -> norm_mult_e e p xs

(* converts add_ter -> exp *)

(* pre : no negative signs
   converts [add_term] -> exp *)
let add_term_to_exp (xs:add_term_list) : exp =
  let to_exp (i,e) =
    if (i<0) then mk_err "add_term has -ve sign" else
      match e with
      | C _ -> IConst(i,no_pos)
      | V v -> if (i==1) then Var(v,no_pos)
        else Mult(IConst(i,no_pos),Var(v,no_pos),no_pos)
      | E e -> if (i==1) then e
        else Mult (IConst(i,no_pos),e,no_pos) in 
  match xs with
  | [] -> IConst (0,no_pos)
  | x::xs -> List.fold_left (fun e r -> 
      let e2=to_exp r in Add (e,e2,no_pos)) (to_exp x) xs

(* pre : no negative powers
   converts [mult_term] -> exp *)
let mult_term_to_exp (xs:mult_term_list) : exp =
  let rec power e i = if i==1 then e else Mult(e,power e (i-1), no_pos) in
  let to_exp (e,i) =
    if (i<0) then mk_err "mult_term has -ve power" else
      match e with
      | C c -> IConst(c,no_pos)
      | V v -> power (Var(v,no_pos)) i
      | E e -> power e i in
  match xs with
  | [] -> IConst (1,no_pos)
  | x::xs -> List.fold_left (fun e r -> 
      let e2=to_exp r in Mult(e,e2,no_pos)) (to_exp x) xs

let split_add_term (xs:add_term_list) : (add_term_list * add_term_list) = List.partition (fun (i,_) -> i>0) xs

let split_mult_term (xs:mult_term_list) : (mult_term_list * mult_term_list)  = List.partition (fun (_,i) -> i>0) xs

let op_inv rs = List.map (fun (x,i) -> (x,-i)) rs
let op_neg rs = List.map (fun (i,x) -> (-i,x)) rs
let op_mult r1 r2 = r1@r2
let op_div r1 r2 = r1@(op_inv r2)

let op_add r1 r2 = r1@r2
let op_sub r1 r2 = op_add r1 (op_neg r2)

(* move to util.ml later *)
let assoc_op_part (split:'a -> 'a list) (comb: 'a -> ('b list) list -> 'b list)
    (base:'a->'b list) (e:'a) : 'b list =
  let rec helper e =
    match (split e) with
    | [] -> base e
    | xs -> let r = List.map (helper) xs in
      comb e r
  in helper e


(* (e1*e2)/(e3*e4) ==> [e1^1,e2^1,e3^-1,e4^-1] *)

let assoc_mult (e:exp) : mult_term_list =
  let split e = match e with
    | Mult (e1,e2,_) -> [e1;e2]
    | Div (e1,e2,_) -> [e1;e2]
    | _ -> [] in
  let comb e args = match (e,args) with
    | (Mult _,[r1;r2]) -> op_mult r1 r2
    | (Div _,[r1;r2]) -> op_div r1 r2
    | _,_ ->  mk_err "comb assoc_mult : mismatch number of arguments! " in
  let base e = match e with
    | IConst (i,_) -> [(C i,1)]
    | Var (v,_)  -> [(V v, 1)]
    | e      -> [(E e,1)]
  in assoc_op_part split comb base  e

let normalise_mult (e:exp) : exp =
  let al=assoc_mult e
  in mult_term_to_exp(norm_mult (sort_mult_term al))

(* (e1+e2)-(e3+e4) ==> [e1,e2,-e3,-e4] *)

let assoc_add (e:exp) : add_term_list =
  let  split e = match e with
    | Add (e1,e2,_) -> [e1;e2]
    | Subtract (e1,e2,_) -> [e1;e2]
    (* | Neg (e1,_) -> [e1] *)
    | _ -> [] in
  let comb e args = match e, args with
    | Add _,[r1;r2] -> op_add r1 r2
    | Subtract _,[r1;r2] -> op_sub r1 r2
    (* | Neg _,[r] -> op_neg r *)
    | _ -> mk_err "comb in assoc_add : mismatch number of arguments! " in
  let base e = match e with
    | IConst (i,_) -> [(i, C 1)]
    | Var (v,_)  -> [(1, V v)]
    | e      -> let e1=normalise_mult e in [(1, E e1)]
  in assoc_op_part split comb base  e

let normalise_add (e:exp) : exp =
  let al=assoc_add e
  in add_term_to_exp(norm_add (sort_add_term al))

let normalise_two_sides (e1:exp) (e2:exp) : (exp * exp) =
  let a1=assoc_add e1 in
  let a2=assoc_add e2 in
  let al=op_sub a1 a2 in
  let al=norm_add(sort_add_term al) in
  let (r1,r2)=List.partition (fun (i,_) -> i>=0) al in
  ((add_term_to_exp r1),(add_term_to_exp r2))

let assoc_min (e:exp) : add_term_list list =
  let  split e = match e with
    | Min (e1,e2,_) -> [e1;e2]
    | _ -> [] in
  let comb e args = match e, args with
    | Min _,[r1;r2] -> op_add r1 r2
    | _ -> mk_err "comb in assoc_min : mismatch number of arguments! " in
  let base e = [assoc_add e]
  in assoc_op_part split comb base  e

let assoc_max (e:exp) : add_term_list list =
  let  split e = match e with
    | Max (e1,e2,_) -> [e1;e2]
    | _ -> [] in
  let comb e args = match e, args with
    | Max _,[r1;r2] -> op_add r1 r2
    | _ -> mk_err "comb in assoc_max : mismatch number of arguments! " in
  let base e = [assoc_add e]
  in assoc_op_part split comb base  e

(* normalise and simplify b_formula *)
let norm_bform_b (bf:b_formula) : b_formula =
  (*let bf = x_add_1 b_form_simplify bf in *)
  let (pf,il) = bf in
  let npf = let rec helper pf = 
              match pf with 
              | Lt  (e1,e2,l) -> 
                if contains_inf e1 || contains_inf e2 then pf else
                  let e1= (Add(e1,IConst(1,no_pos),l)) in 
                  let (e1,e2) = normalise_two_sides e1 e2 in
                  norm_bform_leq e1 e2 l 
              | Lte (e1,e2,l) -> 
                let (e1,e2) = normalise_two_sides e1 e2 in
                norm_bform_leq e1 e2 l 
              | Gt  (e1,e2,l) -> 
                if contains_inf e1 || contains_inf e2 then pf else
                  let e1,e2= (Add(e2,IConst(1,no_pos),l),e1) in 
                  let (e1,e2) = normalise_two_sides e1 e2 in
                  norm_bform_leq e1 e2 l 
              | Gte (e1,e2,l) ->  
                let (e1,e2) = normalise_two_sides e2 e1 in
                norm_bform_leq e1 e2 l 
              | Eq  (e1,e2,l) -> 
                let (e1,e2) = normalise_two_sides e1 e2 in
                norm_bform_eq e1 e2 l 
              | Neq (e1,e2,l) -> 
                let (e1,e2) = normalise_two_sides e1 e2 in
                norm_bform_neq e1 e2 l  
              | BagIn (v,e,l) -> BagIn (v, norm_exp e, l)
              | BagNotIn (v,e,l) -> BagNotIn (v, norm_exp e, l)
              | ListIn (e1,e2,l) -> ListIn (norm_exp e1,norm_exp e2,l)
              | ListNotIn (e1,e2,l) -> ListNotIn (norm_exp e1,norm_exp e2,l)
              | RelForm (v,es,l) -> RelForm (v, List.map norm_exp es, l)
              | ImmRel  (r,cond,l) -> ImmRel (helper r, cond, l)
              | LexVar t_info -> LexVar { t_info with
                                          lex_exp = List.map norm_exp t_info.lex_exp; 
                                          lex_tmp = List.map norm_exp t_info.lex_tmp; }
              | SubAnn _
              (* | VarPerm _ *)
              | Frm _ | XPure _ | BConst _ | BVar _ | EqMax _ 
              | EqMin _ |  BagSub _ | BagMin _ 
              | BagMax _ | ListAllN _ | ListPerm _ -> pf
    in helper pf
  in (npf, il)

let filter_disj_x disj_ps ps=
  let filter_one_disj p=
    let disjs = split_disjunctions p in
    let rem_disjs = List.filter (fun p1 -> (List.exists (equalFormula p1) ps)) disjs in
    join_disjunctions rem_disjs
  in
  let filtered_disj_ps = List.map filter_one_disj disj_ps in
  filtered_disj_ps

let filter_disj disj_ps ps=
  let pr1 = pr_list !print_formula in
  Debug.no_2 "filter_disj" pr1 pr1 pr1
    (fun _ _ -> filter_disj_x disj_ps ps) disj_ps ps
let rec extract_xpure p=
  match p with
  | BForm (b,_) ->  extract_xpure_b_form_xpure b
  | _ -> report_error no_pos "cpure.extract_xpure"

and extract_xpure_b_form_xpure (b: b_formula) = let (pf,_) = b in
  match pf with
  | XPure xp -> let hp = SpecVar (HpT, xp.xpure_view_name,Unprimed) in
    let args= match xp.xpure_view_node with
      | None -> xp.xpure_view_arguments
      | Some r -> r::xp.xpure_view_arguments
    in
    (hp,args)
  | _ -> report_error no_pos "cpure.extract_xpure"

let rec get_xpure p0=
  let rec helper p=
    match p with
    | BForm (b,_) -> get_xpure_b_form_xpure b
    | And (b1,b2,_) -> (helper b1)@(helper b2)
    | AndList b-> List.fold_left (fun ls (_,b1) -> ls@(helper b1)) [] b
    | Or (b1,b2,_,_) -> (helper b1)@(helper b2)
    | Not (b,_,_) -> helper b
    | Forall (_,b,_,_)-> 	helper b
    | Exists (q,b,lbl,l)-> helper b
  in
  helper p0

and get_xpure_b_form_xpure (b: b_formula) = let (pf,_) = b in
  match pf with
  | XPure xp -> let hp = SpecVar (HpT, xp.xpure_view_name,Unprimed) in
    let args= match xp.xpure_view_node with
      | None -> xp.xpure_view_arguments
      | Some r -> r::xp.xpure_view_arguments
    in
    [(hp,args)]
  | _ -> []

and drop_xpure_pformula pf= match pf with
  | XPure xp -> BConst (true, xp.xpure_view_pos)
  | _ -> pf

and drop_xpure_bformula (pf, a) =  (drop_xpure_pformula pf, a)

and drop_xpure f0 =
  let rec helper f=
    match f with
    | BForm (bf, ofl) -> BForm (drop_xpure_bformula bf, ofl)
    | And (f1, f2, p) -> begin
        let nf1 = helper f1 in
        let nf2 = helper f2 in
        match isConstTrue nf1, isConstTrue nf2 with
        | true, true -> mkTrue p
        | true, false -> nf2
        | false, true -> nf1
        | false,false -> And (nf1, nf2, p)
      end
    | AndList b -> AndList (map_l_snd helper b)
    | Or (f1, f2, ofl, p) ->  Or (helper f1, helper f2, ofl, p)
    | Not (f, ofl, p) ->  Not (helper f, ofl, p)
    | Forall (sv, f, ofl, p) -> Forall (sv, helper f, ofl, p)
    | Exists (sv, f, ofl, p) -> Exists (sv, helper f, ofl, p)
  in
  helper f0


(***********************************
 * aggressive simplify and normalize
 * of arithmetic formulas
 **********************************)
module ArithNormalizer = struct

  (* 
   * Printing functions, mainly here for debugging purposes
   *)
  let rec string_of_exp e0 =
    let need_parentheses e = match e with
      | Add _ | Subtract _ -> true
      | _ -> false
    in let wrap e =
      if need_parentheses e then "(" ^ (string_of_exp e) ^ ")"
      else (string_of_exp e)
    in
    match e0 with
    | Null _ -> "null"
    | Var (v, _) -> string_of_spec_var v
    | IConst (i, _) -> string_of_int i
    | FConst (f, _) -> string_of_float f
    | AConst (f, _) -> string_of_heap_ann f
    | Tsconst (f,_) -> Tree_shares.Ts.string_of f
    | Add (e1, e2, _) -> (string_of_exp e1) ^ " + " ^ (string_of_exp e2)
    | Subtract (e1, e2, _) -> (string_of_exp e1) ^ " - " ^ (string_of_exp e2)
    | Mult (e1, e2, _) -> (wrap e1) ^ "*" ^ (wrap e2)
    | Div (e1, e2, _) -> (wrap e1) ^ "/" ^ (wrap e2)
    | Max (e1, e2, _) -> "max(" ^ (string_of_exp e1) ^ "," ^ (string_of_exp e2) ^ ")"
    | Min (e1, e2, _) -> "min(" ^ (string_of_exp e1) ^ "," ^ (string_of_exp e2) ^ ")"
    | TypeCast (ty, e1, _) -> "(" ^ (Globals.string_of_typ ty) ^ ") " ^ string_of_exp e1
    | ArrayAt (sv,elst,_)->
      let string_of_index_list
          (elst:exp list):string=
        List.fold_left (fun s e -> s ^"["^(string_of_exp e)^"]") "" elst
      in
      (string_of_spec_var sv)^(string_of_index_list elst) 
    | _ -> "???"

  let string_of_b_formula bf = 
    let build_exp e1 e2 op =
      (string_of_exp e1) ^ op ^ (string_of_exp e2) in
    let (pf,il) = bf in
    let spf = match pf with
      | XPure _ -> "XPURE?"
      | BConst (b, _) -> (string_of_bool b)
      | BVar (bv, _) -> (string_of_spec_var bv) ^ " > 0"
      | Lt (e1, e2, _) -> build_exp e1 e2 " < "
      | SubAnn (e1, e2, _) -> build_exp e1 e2 " <: "
      | Lte (e1, e2, _) -> build_exp e1 e2 " <= "
      | Gt (e1, e2, _) -> build_exp e1 e2 " > "
      | Gte (e1, e2, _) -> build_exp e1 e2 " >= "
      | Eq (e1, e2, _) -> build_exp e1 e2 " = "
      | Neq (e1, e2, _) -> build_exp e1 e2 " != "
      | EqMax (e1, e2, e3, _) ->
        (string_of_exp e1) ^ " = max(" ^ (string_of_exp e2) ^ "," ^ (string_of_exp e3) ^ ")"
      | EqMin (e1, e2, e3, _) ->
        (string_of_exp e1) ^ " = min(" ^ (string_of_exp e2) ^ "," ^ (string_of_exp e3) ^ ")"
      | _ -> "???" in
    let sil = match il with
      | None -> ""
      | _ -> "$[]"
    in sil ^ spf

  type add_term = int * mult_term_list

  type add_term_list = add_term list (* default [] means 0 *)

  let neg_add_term_list (terms: add_term_list) =
    List.map (fun (i, x) -> (-i, x)) terms

  let mult_2_add_terms (t1: add_term) (t2: add_term) : add_term =
    let i1, mt1 = t1 in
    let i2, mt2 = t2 in
    (i1*i2, mt1@mt2)

  (*
   * create a add_terms list from given exp
   * faltten the expression by distributing all multiplications over addition sub-exp
   * e.g.:
   *   a*(b+c) -> a*b + a*c
   *   (a+b)*(c+d) -> a*c + a*d + b*c + b*d
   *)
  let rec explode_exp (e: exp) : add_term_list = match e with
    | Add (e1, e2, _) -> (explode_exp e1) @ (explode_exp e2)
    | Subtract (e1, e2, _) -> (explode_exp e1) @ (neg_add_term_list (explode_exp e2))
    | Mult (e1, e2, _) ->
      let terms1 = explode_exp e1 in
      let terms2 = explode_exp e2 in
      List.flatten (List.map (fun t -> List.map (mult_2_add_terms t) terms2) terms1)
    | Div (e1, e2, _) -> [1, [E e, 1]] (* FIXME: to be implemented *)
    | Null _ -> []
    | Var (sv, _) -> [1, [V sv, 1]]
    | IConst (i, _) -> [1, [C i, 1]]
    | _ -> [1, [E e, 1]]

  (* convert a m_add_term to corresponding exp form 
   * also simplify the case coeff = 0 or 1 and empty mult_terms list
  *)
  let add_term_to_exp (term: add_term) : exp =
    let i, mtl = term in
    if i = 0 || mtl = [] then 
      IConst (i, no_pos)
    else if i = 1 then
      mult_term_to_exp mtl
    else
      Mult (IConst (i, no_pos), mult_term_to_exp mtl, no_pos)

  (* convert a list of add_terms back to correspondding exp form *)
  let rec add_term_list_to_exp (terms: add_term_list) : exp =
    match terms with
    | [] -> IConst (0, no_pos)
    | [term] -> add_term_to_exp term
    | head::tail -> 
      let i, mtl = head in
      if i = 0 then
        add_term_list_to_exp tail
      else
        Add (add_term_to_exp head, add_term_list_to_exp tail, no_pos)

  (* compare two lists
   * most significant item is the head of the list
   * list with smaller length will be considered less than the other
  *)
  let rec cmp_list (l1: 'a list) (l2: 'a list) (fcmp: 'a -> 'a -> int) : int =
    match l1, l2 with
    | [], [] -> 0
    | [], _ -> -1
    | _, [] -> 1
    | h1::r1, h2::r2 ->
      let cmp_head = fcmp h1 h2 in
      if cmp_head = 0 then
        cmp_list r1 r2 fcmp
      else cmp_head

  let norm_add_term (term: add_term) : add_term =
    let i, mlist = term in
    let normalized_mult_terms = norm_mult (sort_mult_term mlist) in
    let res = match normalized_mult_terms with
      | (C c, _)::r -> (i*c, r)
      | _ -> (i, normalized_mult_terms)
    in res

  (* sort the list of add_terms after normalizing each m_add_term
  *)
  let sort_add_term_list (terms: add_term_list) : add_term_list =
    let cmp (_, x) (_, y) = cmp_list x y cmp_mult_term in
    List.sort cmp (List.map norm_add_term terms)

  let rec norm_add_term_list (terms: add_term_list) : add_term_list =
    let terms = sort_add_term_list terms in
    let rec insert (term: add_term) (termlist: add_term_list) : add_term_list = 
      let i1, mtl1 = term in
      if i1 = 0 then
        termlist
      else
        match termlist with
        | [] -> [term]
        | head::tail ->
          let i2, mtl2 = head in
          if (cmp_list mtl1 mtl2 cmp_mult_term) = 0 then
            insert (i1+i2, mtl1) tail
          else
            term::termlist
    in
    match terms with
    | [] -> []
    | head::tail -> insert head (norm_add_term_list tail)

  let norm_two_sides (e1:exp) (e2:exp) : (exp * exp) =
    let aterms1 = explode_exp e1 in
    let aterms2 = explode_exp e2 in
    let terms = norm_add_term_list (aterms1 @ (neg_add_term_list aterms2)) in
    let lhs_terms, rhs_terms = List.partition (fun (i, _) -> i >= 0) terms in
    let rhs_terms = neg_add_term_list rhs_terms in
    (add_term_list_to_exp lhs_terms), (add_term_list_to_exp rhs_terms)

  let norm_two_sides_debug e1 e2 =
    Debug.no_2 "cpure::norm_two_sides" string_of_exp string_of_exp 
      (fun (x,y) -> (string_of_exp x) ^ " | " ^ (string_of_exp y))
      norm_two_sides e1 e2

  let norm_exp (e: exp) : exp =
    let term_list = norm_add_term_list (explode_exp e) in
    add_term_list_to_exp term_list

  let norm_exp_debug e =
    Debug.no_1 "cpure::norm_exp" string_of_exp string_of_exp norm_exp e

  let norm_bform_relation rel e1 e2 l makef = match e1, e2 with
    | IConst (i1, _), IConst (i2, _) -> BConst (rel i1 i2, l)
    | _ -> makef (e1, e2, l)

  let norm_bform_leq e1 e2 l =
    norm_bform_relation (<=) e1 e2 l (fun x -> Lte x)

  let norm_bform_eq e1 e2 l = 
    norm_bform_relation (=) e1 e2 l (fun x -> Eq x)

  let norm_bform_neq e1 e2 l = 
    norm_bform_relation (<>) e1 e2 l (fun x -> Neq x)

  let test_null e1 e2 =
    match e1 with
    | Null _ -> Some (e2,e1)
    | _ -> (match e2 with
        | Null _ -> Some (e1,e2) 
        | _ -> None
      )

  let norm_b_formula (bf: b_formula) : b_formula option =
    let (pf,il) = bf in
    let npf = match pf with
      | Lt (e1, e2, l) -> 
        if contains_inf e1 || contains_inf e2 then Some(pf) else
          let e1 = Add (e1, IConst(1, no_pos), l) in 
          let lhs, rhs = norm_two_sides e1 e2 in
          Some (norm_bform_leq lhs rhs l)
      | Lte (e1, e2, l) -> 
        let lhs, rhs = norm_two_sides e1 e2 in
        Some (norm_bform_leq lhs rhs l)
      | Gt (e1, e2, l) -> 
        if contains_inf e1 || contains_inf e2 then Some(pf) else
          let e1, e2 = Add (e2, IConst(1, no_pos), l), e1 in 
          let lhs, rhs = norm_two_sides e1 e2 in
          Some (norm_bform_leq lhs rhs l)
      | Gte (e1, e2, l) ->  
        let lhs, rhs = norm_two_sides e2 e1 in
        Some (norm_bform_leq lhs rhs l)
      | Eq (e1, e2, l) ->
        begin
          match test_null e1 e2 with
          | None ->
            let lhs, rhs = norm_two_sides e1 e2 in
            Some (norm_bform_eq lhs rhs l)
          | Some (e1,e2) -> Some (Eq (e1,e2,l))
        end
      | Neq (e1, e2, l) -> 
        begin
          match test_null e1 e2 with
          | None ->
            let lhs, rhs = norm_two_sides e1 e2 in
            Some (norm_bform_neq lhs rhs l)
          | Some (e1,e2) -> Some (Neq (e1,e2,l))
        end
      | _ -> None
    in match npf with
    | None -> None
    | Some pf -> Some (pf,il)

  let norm_formula (f: formula) : formula =
    if (is_float_formula f || not !Globals.allow_norm) then f else
      map_formula f (nonef, norm_b_formula, fun e -> Some (norm_exp e)) 


end (* of ArithNormalizer module's definition *)

let norm_form f =
  if (not !Globals.allow_norm) then f else
    ArithNormalizer.norm_formula f 

let norm_form f =
  let pr = !print_formula in
  Debug.no_1 "cpure::norm_formula" 
    pr pr
    norm_form f

let has_var_exp e0 =
  let f e = match e with
    | Var _ -> Some true
    | _ -> None
  in
  fold_exp e0 f or_list 

let is_linear_formula f0 =
  let f_bf bf = 
    if is_bag_bform bf || is_list_bform bf then
      Some false
    else None
  in
  let f_e e =
    if is_bag e || is_list e then 
      Some false
    else
      match e with
      | Mult (e1, e2, _) -> 
        if has_var_exp e1 && has_var_exp e2 then
          Some false
        else None
      | Div (e1, e2, _) -> Some false
      | _ -> None
  in
  fold_formula f0 (nonef, f_bf, f_e) and_list

let is_linear_formula f0 =
  Debug.no_1 "is_linear_formula" !print_formula string_of_bool is_linear_formula f0

let is_linear_exp e0 =
  let f e =
    if is_bag e || is_list e then 
      Some false
    else
      match e with
      | Mult (e1, e2, _) -> 
        if has_var_exp e1 && has_var_exp e2 then
          Some false
        else None
      | Div (e1, e2, _) -> Some false
      | _ -> None
  in
  fold_exp e0 f and_list

let inner_simplify simpl f =
  (* Thai: Why only simplify with Exists stms? *)
  let f_f e = match e with
    | Exists _ -> (Some (simpl e))
    | _ -> None in
  let f_bf bf = None in
  let f_e e = (Some e) in
  map_formula f (f_f, f_bf, f_e) 


let rec elim_exists_with_simpl_x simpl (f0 : formula) : formula = 
  let f = elim_exists f0 in
  inner_simplify simpl f

and elim_exists_with_simpl simpl (f0 : formula) : formula = 
  Debug.no_1 "elim_exists_with_simpl" !print_formula !print_formula 
    (fun f0 -> elim_exists_with_simpl_x simpl f0) f0

(* Method checking whether a formula contains bag constraints or BagT vars *)
and is_bag_b_constraint (pf,_) = match pf with
  | BConst _ 
  | BVar _
  | Lt _ 
  | Lte _ 
  | Gt _ 
  | Gte _
  | EqMax _ 
  | EqMin _
  | ListIn _ 
  | ListNotIn _
  | ListAllN _ 
  | ListPerm _
    -> Some false
  | BagIn _ 
  | BagNotIn _
  | BagMin _ 
  | BagMax _
  | BagSub _
    -> Some true
  | _ -> None

(* Strict: include bag vars *)
and is_bag_constraint (e: formula) : bool =  
  let f_e e = match e with
    | Bag _
    | BagUnion _
    | BagIntersect _
    | BagDiff _ 
      -> Some true
    | Var (SpecVar (t, _, _), _) -> 
      (match t with
       | BagT _ -> Some true
       | _ -> Some false)
    | _ -> Some false
  in
  let or_list = List.fold_left (||) false in
  fold_formula e (nonef, is_bag_b_constraint, f_e) or_list

and has_level_constraint_x (f: formula) : bool =
  let f_e e =
    let rec helper e =
      match e with
      | Level _ -> true
      | BagDiff (e1,e2,_)
      | ListCons(e1,e2,_)
      | Add (e1,e2,_)  | Subtract (e1,e2,_)  | Mult (e1,e2,_) 
      | Div (e1,e2,_)  | Max (e1,e2,_)  | Min (e1,e2,_) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        (res1||res2)
      | TypeCast (_, e1, _) -> helper e1
      | List (exps,_)
      | ListAppend (exps,_)
      | ArrayAt (_,exps,_)
      | Func (_,exps,_)
      | Bag (exps,_)
      | BagUnion (exps,_)
      | BagIntersect (exps,_) ->
        let ress = List.map helper exps in
        (List.exists (fun v -> v) ress)
      | ListHead (e,_)
      | ListTail (e,_) 
      | ListLength (e,_)
      | ListReverse (e,_) ->
        helper e
      | _ -> false
    in
    let res = helper e in
    Some res
  in
  let or_list = List.fold_left (||) false in
  fold_formula f (nonef, nonef, f_e) or_list

and has_level_constraint (f: formula) : bool =
  Debug.no_1 "has_level_constraint"
    !print_formula string_of_bool
    has_level_constraint_x f

and has_level_constraint_exp (e: exp) : bool =
  let rec helper e =
    match e with
    | Level _ -> true
    | BagDiff (e1,e2,_)
    | ListCons(e1,e2,_)
    | Add (e1,e2,_)  | Subtract (e1,e2,_)  | Mult (e1,e2,_) 
    | Div (e1,e2,_)  | Max (e1,e2,_)  | Min (e1,e2,_) ->
      let res1 = helper e1 in
      let res2 = helper e2 in
      (res1||res2)
    | TypeCast (_, e1, _) -> helper e1
    | List (exps,_)
    | ListAppend (exps,_)
    | ArrayAt (_,exps,_)
    | Func (_,exps,_)
    | Bag (exps,_)
    | BagUnion (exps,_)
    | BagIntersect (exps,_) ->
      let ress = List.map helper exps in
      (List.exists (fun v -> v) ress)
    | ListHead (e,_)
    | ListTail (e,_) 
    | ListLength (e,_)
    | ListReverse (e,_) ->
      helper e
    | _ -> false
  in
  helper e

(* result of xpure with baga and memset/diffset *)
type xp_res_type = (BagaSV.baga * DisjSetSV.dpart * formula)

(*
(S1,D1,P1) * (S2,D2,P2)  =   (S1+S2, D1&D2,P1&P2)

(S1,D1,P1) & (S2,D2,P2)  = 
  (S1{\cap}S2, S1::D1 & S2::D2,
            (SAT(S1)&SAT(S2)) & P1&P2 )
(S1,D1,P1) \/ (S2,D2,P2) = 
  (S1{\cap}S2, SAT(S1)->S1::D1\/SAT(S2)->S1::D2, 
        SAT(S1) & P1 \/ SAT(S2) & P2)
*)

let star_xp_res ((b1,d1,p1):xp_res_type) ((b2,d2,p2):xp_res_type) =
  (BagaSV.star_baga b1 b2, DisjSetSV.star_disj_set d1 d2, mkAnd p1 p2 no_pos)

let conj_xp_res ((b1,d1,p1):xp_res_type) ((b2,d2,p2):xp_res_type) =
  let nb = BagaSV.conj_baga b1 b2 in
  let nd = DisjSetSV.conj_disj_set (b1::d1) (b2::d2) in
  let np = if (BagaSV.is_sat_baga b1) && (BagaSV.is_sat_baga b1) then  mkAnd p1 p2 no_pos  else mkFalse no_pos in
  (nb,nd,np)

let or_xp_res  ((b1,d1,p1):xp_res_type) ((b2,d2,p2):xp_res_type) =
  let nb = BagaSV.or_baga b1 b2 in
  let (np1,nd1) = if (BagaSV.is_sat_baga b1) then (p1,Some (b1::d1)) else (mkFalse no_pos,None) in
  let (np2,nd2) = if (BagaSV.is_sat_baga b2) then (p2,Some (b2::d2)) else (mkFalse no_pos,None) in
  let nd = match nd1,nd2 with
    | None,None -> []
    | None,Some nd2 -> nd2
    | Some nd1,None -> nd1
    | Some nd1,Some nd2 ->  DisjSetSV.or_disj_set (b1::d1) (b2::d2) in
  (nb,nd, mkOr np1 np2 None no_pos)


let rec filter_complex_inv f = match f with
  | And (f1,f2,l) -> mkAnd (filter_complex_inv f1) (filter_complex_inv f2) l
  | AndList b -> AndList (map_l_snd filter_complex_inv b)
  | Or _ -> f  
  | Forall _ -> f
  | Exists _ -> f
  | Not (_,_,l) -> mkTrue l
  | BForm ((pf,il),l) -> match pf with
    | XPure _  
    | BConst _  
    | BVar _ 
    | BagSub _
    | BagMin _
    | BagMax _
    | ListAllN _
    | ListPerm _
    | RelForm _ -> f
    | _ -> mkTrue no_pos

let mkNot_norm f lbl1 pos0 :formula= match f with
  | BForm (bf,lbl) ->
    begin
      let r =
        let (pf,il) = bf in
        match pf with
        | BConst (b, pos) -> Some (BConst ((not b), pos))
        | Lt (e1, e2, pos) -> Some (Gte (e1, e2, pos))
        | Lte (e1, e2, pos) -> Some(Gt (e1, e2, pos))
        | Gt (e1, e2, pos) -> Some(Lte (e1, e2, pos))
        | Gte (e1, e2, pos) -> Some(Lt (e1, e2, pos))
        | Eq (e1, e2, pos) -> Some(Neq (e1, e2, pos))
        | Neq (e1, e2, pos) -> Some(Eq (e1, e2, pos))
        | BagIn e -> Some(BagNotIn e)
        | BagNotIn e -> Some(BagIn e)
        | _ -> None in
      match r with 
      | None -> Not (f, lbl,pos0)
      | Some pf -> BForm((norm_bform_aux bf),lbl)
    end
  | _ -> Not (f, lbl1,pos0)


let mkNot_b_norm (bf : b_formula) : b_formula option = 
  let r =
    let (pf,il) = bf in
    match pf with
    | BConst (b, pos) -> Some ((BConst ((not b), pos)), il)
    | Lt (e1, e2, pos) -> Some ((Gte (e1, e2, pos)), il)
    | Lte (e1, e2, pos) -> Some ((Gt (e1, e2, pos)), il)
    | Gt (e1, e2, pos) -> Some ((Lte (e1, e2, pos)), il)
    | Gte (e1, e2, pos) -> Some ((Lt (e1, e2, pos)), il)
    | Eq (e1, e2, pos) -> Some ((Neq (e1, e2, pos)), il)
    | Neq (e1, e2, pos) -> Some ((Eq (e1, e2, pos)), il)
    | BagIn e -> Some ((BagNotIn e), il)
    | BagNotIn e -> Some ((BagIn e), il)
    | _ -> None in
  match r with 
  | None -> None
  | Some bf -> Some (norm_bform_aux bf)



let filter_constraint_type (ante: formula) (conseq: formula) : (formula) = 
  if (!Globals.enable_constraint_based_filtering) then 
    let conseq_disjs = list_of_disjs conseq in 
    if List.length conseq_disjs == 1 then
      let disjs = list_of_disjs ante in 
      let helper f = 
        let antes = list_of_conjs ante in
        (*let todo_unk = List.map (fun c -> print_string ("Antes : "^(!print_formula c)^"\n")) antes in *)
        let filtered_antes = if List.exists (fun c -> eq_pure_formula conseq c) antes then
            List.filter (fun c -> eq_pure_formula conseq c) antes else 
          if is_bag_constraint conseq then antes
          (*List.filter (fun c -> is_bag_constraint c || contains_exists c)  antes*)
          else List.filter (fun c -> not(is_bag_constraint c) (*|| contains_exists c*)) antes in 
        join_conjunctions filtered_antes in 
      let filtered_disjs = List.map helper disjs in
      join_disjunctions filtered_disjs 
    else ante
  else ante

let filter_constraint_type (ante: formula) (conseq: formula) : (formula) = 
  let pr = !print_formula in
  Debug.no_2 "filter_constraint_type" pr pr pr filter_constraint_type ante conseq

let filter_constraint_type (ante: formula) (conseq: formula) : (formula) = 
  if (!Globals.enable_constraint_based_filtering) then 
    let conseq_disjs = list_of_disjs conseq in 
    if List.length conseq_disjs == 1 then
      let disjs = list_of_disjs ante in 
      let helper f = 
        let antes = list_of_conjs ante in
        (*let todo_unk = List.map (fun c -> print_string ("Antes : "^(!print_formula c)^"\n")) antes in *)
        let filtered_antes = if List.exists (fun c -> eq_pure_formula conseq c) antes then
            List.filter (fun c -> eq_pure_formula conseq c) antes else 
          if is_bag_constraint conseq then antes
          (*List.filter (fun c -> is_bag_constraint c || contains_exists c)  antes*)
          else List.filter (fun c -> not(is_bag_constraint c) || contains_exists c) antes in 
        join_conjunctions filtered_antes in 
      let filtered_disjs = List.map helper disjs in
      join_disjunctions filtered_disjs 
    else ante
  else ante

let filter_constraint_type (ante: formula) (conseq: formula) : (formula) = 
  let pr = !print_formula in
  Debug.no_2 "filter_constraint_type" pr pr pr filter_constraint_type ante conseq



let filter_ante (ante : formula) (conseq : formula) : (formula) =
  let fvar = fv conseq in
  let ante = filter_var ante fvar in
  let new_ante = if (!Globals.enable_constraint_based_filtering) then filter_constraint_type ante conseq else ante in
  new_ante

let filter_ante (ante: formula) (conseq: formula) : (formula) = 
  let pr = !print_formula in
  Debug.no_2 "filter_ante" pr pr pr filter_ante ante conseq

let filter_ante_wo_rel (ante : formula) (conseq : formula) : (formula) =
  let fvar = fv conseq in
  let fvar = List.filter (fun v -> not(is_rel_var v)) fvar in
  let new_ante = filter_var ante fvar in
  new_ante

let filter_ante_wo_rel (ante: formula) (conseq: formula) : (formula) = 
  let pr = !print_formula in
  Debug.no_2 "filter_ante_wo_rel" pr pr pr filter_ante_wo_rel ante conseq

(* automatic slicing of variables *)

(* slice_formula inp1 :[ 0<=x, 0<=y, z<x] *)
(* slice_formula@22 EXIT out :[([z,x],[ z<x, 0<=x]),([y],[ 0<=y])] *)

let elim_equi_var f qvar=
  let st, pp1 = get_subst_equation_formula f qvar false in
  if not (Gen.is_empty st) then
    subst_term st pp1
  else f

let rec get_equi_vars_x (f : formula) : (spec_var list) = match f with
  | BForm ((b,a),l) -> get_equi_vars_b b
  | And (f1,f2,l) ->
    let g1 = get_equi_vars_x f1 in
    let g2 = get_equi_vars_x f2 in
    g1@g2
  | Or (f1,f2,l,p) ->
    let g1 = get_equi_vars_x f1 in
    let g2 = get_equi_vars_x f2 in
    g1@g2
  | Not (nf,_,_) -> get_equi_vars_x nf
  | _ -> []

and get_equi_vars f=
  let pr1 = !print_formula in
  Debug.no_1 "get_equi_vars" pr1 !print_svl
    (fun _ -> get_equi_vars_x f) f

and get_equi_vars_b f =
  let helper e=
    match e with
    | Var (sv, _) -> if (is_hole_spec_var sv) then [] else [sv]
    | _ -> []
  in
  match f with
  | Eq (e1,e2,_) -> (helper e1)@(helper e2)
  | Neq (e1,e2,_) -> (helper e1)@(helper e2)
  | _ -> []

let elim_equi_ante_x ante cons=
  let cv = fv cons in
  let eav_all = get_equi_vars ante in
  let eav = List.filter (fun v -> not(mem_svl v cv)) eav_all in
  let () = x_ninfo_hp (add_str "cv" !print_svl) cv no_pos in
  let () = x_ninfo_hp (add_str "eav" !print_svl) eav no_pos in
  if eav =[] then ante else
    List.fold_left elim_equi_var ante eav

let elim_equi_ante ante cons=
  Debug.no_2 "elim_equi_ante"
    !print_formula !print_formula !print_formula
    elim_equi_ante_x ante cons

let slice_formula (fl : formula list) : (spec_var list * formula list) list =
  let repart ac f = 
    let vs = fv f in
    let (ol,nl) = List.partition (fun (vl,f) -> (Gen.BList.overlap_eq eq_spec_var vs vl)) ac in
    let n_vl = List.fold_left (fun a (v,_) -> a@v) vs ol  in
    let n_fl = List.fold_left (fun a (_,fl) -> a@fl) [f] ol  in
    (remove_dups_svl n_vl,n_fl)::nl
  in List.fold_left repart [] fl

let slice_formula (fl : formula list) : (spec_var list * formula list) list =
  let pr = pr_list !print_formula in
  let pr2 = pr_list (pr_pair !print_svl pr) in
  Debug.no_1 "slice_formula" pr pr2 slice_formula fl

let part_contradiction is_sat pairs =
  let (p1,p2) = List.partition (fun (a,c) -> not(is_sat c)) pairs in
  (List.map (fun (_,c) -> (mkTrue no_pos,c) ) p1, p2)

let part_must_failures is_sat pairs = List.partition (fun (a,c) ->not(is_sat (mkAnd a c no_pos))) pairs

let part_must_failures is_sat pairs = List.partition (fun (a,c) -> not(is_sat (mkAnd a c no_pos))) pairs

let imply is_sat a c = not (is_sat (mkAnd a (mkNot c None no_pos) no_pos))

let refine_one_must is_sat (ante,conseq) : (formula * formula) list =
  let cs = split_conjunctions conseq in
  let ml = List.filter (fun c ->
      let f = mkAnd ante c no_pos in
      not(is_sat f)) cs in
  if ml==[] then [(ante,conseq)]
  else List.map (fun f -> (ante,f)) ml

let refine_one_must is_sat (ante,conseq) : (formula * formula) list =

  (* let () = print_string ("refine_one_must: before is_sat" *)
  (*                       ^ "\n\n") in *)

  let pr = !print_formula in
  let pr2 = pr_list (pr_pair pr pr) in
  Debug.no_1 "refine_one_must" (pr_pair pr pr) pr2 (fun  _ ->refine_one_must is_sat (ante, conseq)) (ante, conseq)


let refine_must is_sat (pairs:(formula * formula) list) : (formula * formula) list =

  (* let () = print_string ("refine_must: before is_sat" *)
  (*                       ^ "\n\n") in *)

  let rs = List.map (refine_one_must is_sat) pairs in
  List.concat rs

let find_may_failures imply pairs =
  let pairs = List.map (fun (a,c) -> 
      let cs = split_conjunctions c in
      List.map (fun c -> (a,c)) cs) pairs in
  let pairs = List.concat pairs in
  List.filter (fun (a,c) ->  not(imply a c)) pairs

let rec remove_redundant_helper ls rs=
  match ls with
  | [] -> rs
  | f::fs -> if List.exists (equalFormula f) fs then
      remove_redundant_helper fs rs
    else (match f with
        | BForm ((Eq(e1, e2, _), _) ,_) -> if (eq_exp_no_aset e1 e2) || (is_null_const_exp e1 || is_null_const_exp e2) then
            remove_redundant_helper fs rs
          else remove_redundant_helper fs rs@[f]
        | BForm ((Lte(IConst (0,_), IConst (0,_), _), _) ,_) -> remove_redundant_helper fs rs
        | _ -> remove_redundant_helper fs rs@[f]
      )

let remove_redundant (f:formula):formula =
  let l_conj = split_conjunctions f in
  let prun_l = remove_redundant_helper l_conj [] in
  join_conjunctions prun_l

let remove_redundant (f:formula):formula =
  let pr = !print_formula in
  Debug.no_1 "remove_redundant" pr pr remove_redundant f

let find_all_failures is_sat ante cons =

  (* let () = print_string ("find_all_failures: before is_sat" *)
  (*                       ^ "\n\n") in *)
  (*remove duplicate, a=a*)
  let ante = (*remove_dup_constraints*) remove_redundant ante in
  let cs= split_conjunctions cons in
  let cs = List.map (fun (_,ls) -> join_conjunctions ls) (slice_formula cs) in
  let cand_pairs = List.map (fun c -> (filter_ante ante c,c)) cs in
  let (contra_list,cand_pairs) = part_contradiction is_sat cand_pairs in
  let (must_list,cand_pairs) = part_must_failures is_sat cand_pairs in
  let must_list = refine_must is_sat must_list in

  (* let () = print_string ("find_all_failures: before find_may_failures (imply is_sat) cand_pairs" *)
  (*                       ^ "\n\n") in *)

  let may_list = find_may_failures (imply is_sat) cand_pairs in
  (contra_list,must_list,may_list)

let find_all_failures is_sat  ante cons =
  let pr = !print_formula in
  let pr2 = pr_list (pr_pair pr pr) in
  Debug.no_2 "find_all_failures" pr pr (pr_triple pr2 pr2 pr2) (fun _ _ -> find_all_failures is_sat ante cons) ante cons 

let find_must_failures is_sat ante cons =

  (* let () = print_string ("find_must_failures: before is_sat" *)
  (*                       ^ "\n\n") in *)

  let (contra_list,must_list,_) = find_all_failures is_sat ante cons in
  contra_list@must_list

let find_must_failures is_sat ante cons =
  let pr = !print_formula in
  let pr2 = pr_list (pr_pair pr pr) in
  Debug.no_2 "find_must_failures" pr pr pr2 (fun _ _ -> find_must_failures is_sat ante cons) ante cons 

let check_maymust_failure is_sat ante cons =

  (* let () = print_string ("check_maymust_failure: before is_sat" *)
  (*                       ^ "\n\n") in *)

  let c_l = find_must_failures is_sat ante cons in
  c_l==[]

let check_maymust_failure is_sat ante cons =
  let pr = !print_formula in
  Debug.no_2 "check_maymust_failure" pr pr string_of_bool (fun _ _ -> check_maymust_failure is_sat ante cons) ante cons 

let simplify_filter_ante (simpl: formula -> formula) (ante:formula) (conseq : formula) : formula =
  let n_a =
    if !Globals.simplify_error then
      simpl ante
    else ante 
  in
  filter_ante n_a conseq

let simplify_filter_ante (simpl: formula -> formula) (ante:formula) (conseq : formula) : formula = 
  let pr = !print_formula in
  Debug.no_2 "simplify_filter_ante" pr pr pr (fun _ _ -> simplify_filter_ante simpl ante conseq) ante conseq

(*=================================================*)
(* Forced Slicing                                  *)	
(*=================================================*)

(* For assigning <IL> fields after doing simplify  
   Used by TP.simplify to recover <IL> information *)
(*yet a third function that takes a formula and returns a b_formula list*)
let rec break_formula1 (f: formula) : formula list = match f with
  | BForm _ -> [f]
  | And (f1, f2, _) -> (break_formula1 f1) @ (break_formula1 f2)
  | AndList b -> fold_l_snd break_formula1 b
  | Or (f1, f2, _, _) -> (break_formula1 f1) @ (break_formula1 f2)
  | Not (f, _, _) -> break_formula1 f
  | Forall (_, f, _, _) -> break_formula1 f
  | Exists (_, f, _, _) -> break_formula1 f

let rec break_formula (f: formula) : b_formula list = match f with
  | BForm (bf, _) -> [bf]
  | And (f1, f2, _) -> (break_formula f1) @ (break_formula f2)
  | AndList b -> fold_l_snd break_formula b
  | Or (f1, f2, _, _) -> (break_formula f1) @ (break_formula f2)
  | Not (f, _, _) -> break_formula f
  | Forall (_, f, _, _) -> break_formula f
  | Exists (_, f, _, _) -> break_formula f

and fv_with_slicing_label_new f = (* OUT: (non-linking vars, linking vars) of formula *) 
  match f with
  | BForm (bf, _) -> bfv_with_slicing_label bf
  | And (f1, f2, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new f2 in
    let lkl = remove_dups_svl (lkl1 @ lkl2) in (* non-linking vars should be maintained *)
    let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in 
    let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
    let vs = remove_dups_svl (n_vs1 @ n_vs2) in
    (vs,lkl)
  | AndList b-> 
    let rec hlp b = match b with 
      | [] -> ([],[])
      | (_,x)::t -> 
        let (vs1, lkl1) = fv_with_slicing_label_new x in
        let (vs2, lkl2) = hlp t in
        let lkl = remove_dups_svl (lkl1 @ lkl2) in (* non-linking vars should be maintained *)
        let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in 
        let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
        let vs = remove_dups_svl (n_vs1 @ n_vs2) in
        (vs,lkl) in
    hlp b
  | Or (f1, f2, _, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new f2 in
    let lkl = remove_dups_svl (lkl1 @ lkl2) in
    let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in
    let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
    let vs = remove_dups_svl (n_vs1 @ n_vs2) in
    (vs,lkl)
  | Not (f, _, _) -> fv_with_slicing_label_new f
  | Forall (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)
  | Exists (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)

and fv_with_slicing_label_new_1 f = (* OUT: (non-linking vars, linking vars) of formula *) 
  match f with
  | BForm (bf, _) -> bfv_with_slicing_label bf
  | And (f1, f2, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new_1 f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new_1 f2 in
    let lkl = remove_dups_svl (lkl1 @ lkl2) in
    let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in
    let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
    let vs = remove_dups_svl (n_vs1 @ n_vs2) in
    (vs,lkl)
  | AndList b-> 
    let rec hlp b = match b with 
      | [] -> ([],[])
      | (_,x)::t -> 
        let (vs1, lkl1) = fv_with_slicing_label_new_1 x in
        let (vs2, lkl2) = hlp t in
        let lkl = remove_dups_svl (lkl1 @ lkl2) in
        let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in
        let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
        let vs = remove_dups_svl (n_vs1 @ n_vs2) in
        (vs,lkl) in
    hlp b
  | Or (f1, f2, _, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new_1 f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new_1 f2 in
    let vs = remove_dups_svl (vs1 @ vs2) in
    let n_lkl1 = Gen.BList.difference_eq eq_spec_var lkl1 vs2 in
    let n_lkl2 = Gen.BList.difference_eq eq_spec_var lkl2 vs1 in
    let lkl = remove_dups_svl (n_lkl1 @ n_lkl2) in
    (vs,lkl)
  | Not (f, _, _) -> fv_with_slicing_label_new_1 f
  | Forall (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new_1 f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)
  | Exists (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new_1 f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)

and fv_with_slicing_label_new_2 f = (* OUT: (non-linking vars, linking vars) of formula *) 
  match f with
  | BForm (bf, _) -> bfv_with_slicing_label bf
  | And (f1, f2, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new_2 f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new_2 f2 in
    let vs = remove_dups_svl (vs1 @ vs2) in
    let n_lkl1 = Gen.BList.difference_eq eq_spec_var lkl1 vs2 in
    let n_lkl2 = Gen.BList.difference_eq eq_spec_var lkl2 vs1 in
    let lkl = remove_dups_svl (n_lkl1 @ n_lkl2) in
    (vs,lkl)
  | AndList b-> 
    let rec hlp b = match b with 
      | [] -> ([],[])
      | (_,x)::t -> 
        let (vs1, lkl1) = fv_with_slicing_label_new_2 x in
        let (vs2, lkl2) = hlp t in
        let vs = remove_dups_svl (vs1 @ vs2) in
        let n_lkl1 = Gen.BList.difference_eq eq_spec_var lkl1 vs2 in
        let n_lkl2 = Gen.BList.difference_eq eq_spec_var lkl2 vs1 in
        let lkl = remove_dups_svl (n_lkl1 @ n_lkl2) in
        (vs,lkl) in
    hlp b
  | Or (f1, f2, _, _) ->
    let (vs1, lkl1) = fv_with_slicing_label_new_2 f1 in
    let (vs2, lkl2) = fv_with_slicing_label_new_2 f2 in
    let lkl = remove_dups_svl (lkl1 @ lkl2) in
    let n_vs1 = Gen.BList.difference_eq eq_spec_var vs1 lkl2 in
    let n_vs2 = Gen.BList.difference_eq eq_spec_var vs2 lkl1 in
    let vs = remove_dups_svl (n_vs1 @ n_vs2) in
    (vs,lkl)
  | Not (f, _, _) -> fv_with_slicing_label_new_2 f
  | Forall (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new_2 f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)
  | Exists (sv, f, _, _) ->
    let (vs, lkl) = fv_with_slicing_label_new_2 f in
    let n_vs = Gen.BList.difference_eq eq_spec_var vs [sv] in
    let n_lkl = Gen.BList.difference_eq eq_spec_var lkl [sv] in
    (n_vs, n_lkl)		  

and fv_with_slicing_label f =
  if !Globals.opt_ineq then fv_with_slicing_label_new f
  else fv_with_slicing_label_new_1 f

and bfv_with_slicing_label bf =
  Debug.no_1 "bfv_with_slicing_label" !print_b_formula
    (fun (nlv, lv) -> (pr_list !print_sv nlv) ^ (pr_list !print_sv lv))
    bfv_with_slicing_label_x bf

and bfv_with_slicing_label_x bf = 
  (* OUT: (strongly-linking vars, weakly-linking vars) of b_formula *)
  let (_, sl) = bf in
  let v_bf = bfv bf in
  match sl with
  | None -> (v_bf, [])
  | Some (il, _, el) ->
    if il then ([], v_bf)
    else
      let lv = List.fold_left (fun a e -> a @ (afv e)) [] el in
      let nlv = Gen.BList.difference_eq eq_spec_var v_bf lv in
      (nlv, lv)

let rec formula_linking_vars_exps f =
  match f with
  | BForm (bf, _) -> b_formula_linking_vars_exps bf
  | And (f1, f2, _) ->
    let lv1 = formula_linking_vars_exps f1 in
    let lv2 = formula_linking_vars_exps f2 in
    let u_lv = remove_dups_svl (lv1 @ lv2) in
    let i_lv = Gen.BList.intersect_eq eq_spec_var lv1 lv2 in
    Gen.BList.difference_eq eq_spec_var u_lv i_lv (* Common linking vars will become non-linking vars *)
  | AndList b-> 
    let l = List.map (fun (_,c)->formula_linking_vars_exps c) b in
    let u_lv = remove_dups_svl (List.concat l) in
    let i_lv = match l with | [] -> [] | x::t -> List.fold_left (fun a c-> Gen.BList.intersect_eq eq_spec_var a c) x t in
    Gen.BList.difference_eq eq_spec_var u_lv i_lv
  | Or (f1, f2, _, _) ->
    let lv1 = formula_linking_vars_exps f1 in
    let lv2 = formula_linking_vars_exps f2 in
    let u_lv = remove_dups_svl (lv1 @ lv2) in
    let i_lv = Gen.BList.intersect_eq eq_spec_var lv1 lv2 in
    Gen.BList.difference_eq eq_spec_var u_lv i_lv (* Common linking vars will become non-linking vars *)
  | Not (f, _, _) -> formula_linking_vars_exps f
  | Forall (sv, f, _, _) ->
    let lv = formula_linking_vars_exps f in
    Gen.BList.difference_eq eq_spec_var lv [sv]
  | Exists (sv, f, _, _) ->
    let lv = formula_linking_vars_exps f in
    Gen.BList.difference_eq eq_spec_var lv [sv]

and b_formula_linking_vars_exps bf =
  let (_, sl) = bf in
  match sl with
  | None -> []
  | Some (il, _, el) ->
    if il then []
    else
      let lv = List.fold_left (fun a e -> a @ (afv e)) [] el in
      remove_dups_svl lv

(* Group related vars together after filtering the <IL> formula *)
let rec group_related_vars (bfl: b_formula list) : (spec_var list * spec_var list * b_formula list) list =
  Debug.no_1 "group_related_vars"
    (fun bfl -> List.fold_left (fun acc bf -> acc ^ "\n" ^ (!print_b_formula bf)) "" bfl)
    (fun sv_bfl -> List.fold_left (fun acc1 (svl,lkl,bfl) ->
         acc1 ^ "\n[" ^ (List.fold_left (fun acc2 sv -> acc2 ^ " " ^ (!print_sv sv)) "" svl) ^ " ]"
         ^ "\n[" ^ (List.fold_left (fun acc2 sv -> acc2 ^ " " ^ (!print_sv sv)) "" lkl) ^ " ]"
         ^ " [" ^ (List.fold_left (fun acc2 bf -> acc2 ^ " " ^ (!print_b_formula bf)) "" bfl) ^ " ]") "" sv_bfl) group_related_vars_x bfl

and group_related_vars_x (bfl: b_formula list) : (spec_var list * spec_var list * b_formula list) list = (* bfv = fv1 U fv2 *)
  let repart acc bf =
    let (vs,lkl) = bfv_with_slicing_label bf in
    let (ol, nl) = List.partition (fun (vl,_,_) -> (Gen.BList.overlap_eq eq_spec_var vs vl)) acc in
    let n_vl = List.fold_left (fun a (vl,_,_) -> a@vl) vs ol in
    let n_lkl = List.fold_left (fun a (_,lk,_) -> a@lk) lkl ol in
    let n_bfl = List.fold_left (fun a (_,_,bfl) -> a@bfl) [bf] ol in
    (remove_dups_svl n_vl, remove_dups_svl n_lkl, n_bfl)::nl
  in List.fold_left repart [] bfl

let check_dept vlist (dept_vars_list, linking_vars_list) =
  let dept_vars = Gen.BList.difference_eq eq_spec_var vlist linking_vars_list in
  if ((List.length dept_vars) > 0 &&
      (Gen.BList.list_subset_eq eq_spec_var dept_vars dept_vars_list))
  then (true, Gen.BList.difference_eq eq_spec_var vlist dept_vars_list)
  else (false, [])

(* Slicing: Set <IL> for a formula based on a list of dependent groups *)
let rec set_il_formula_with_dept_list f rel_vars_lst =
  match f with
  | BForm ((pf, _), lbl) ->
    let vl = fv f in
    let is_dept = List.fold_left (fun res rvl -> if (fst res) then res else (check_dept vl rvl)) (false, []) rel_vars_lst in
    let lexp = List.map (fun sv -> mkVar sv no_pos) (snd is_dept) in
    BForm ((pf, Some (not (fst is_dept), Globals.fresh_int(), lexp)), lbl)
  | And (f1, f2, l) -> And (set_il_formula_with_dept_list f1 rel_vars_lst, set_il_formula_with_dept_list f2 rel_vars_lst, l)
  | AndList b -> AndList (map_l_snd (fun c-> set_il_formula_with_dept_list c rel_vars_lst) b)
  | Or (f1, f2, lbl, l) -> Or (set_il_formula_with_dept_list f1 rel_vars_lst, set_il_formula_with_dept_list f2 rel_vars_lst, lbl, l)
  | Not (f, lbl, l) -> Not (set_il_formula_with_dept_list f rel_vars_lst, lbl, l)
  | Forall (sv, f, lbl, l) -> Forall (sv, set_il_formula_with_dept_list f rel_vars_lst, lbl, l)
  | Exists (sv, f, lbl, l) -> Exists (sv, set_il_formula_with_dept_list f rel_vars_lst, lbl, l)

(* Slicing: Substitute vars bound by EX by fresh vars in LHS *)
let rec elim_exists_with_fresh_vars f =
  match f with
  | Exists (v, f1, _, _) -> 
    let SpecVar (t, i, p) = v in
    let nv = SpecVar (t, fresh_old_name i, p) in
    let l,f = elim_exists_with_fresh_vars (subst [v, nv] f1) in
    nv::l,f
  | BForm _ -> [],f
  | And (f1, f2, loc) -> 
    let l1,f1 = elim_exists_with_fresh_vars f1 in
    let l2,f2 = elim_exists_with_fresh_vars f2 in
    l1@l2, And (f1, f2, loc)
  | AndList b -> 
    let l1,l2 = List.fold_left (fun (a1,a2) (l,c)-> 
        let l1,c1 = elim_exists_with_fresh_vars c in
        l1@a1,(l,c1)::a2) ([],[]) b in
    l1, AndList l2 
  | Or (f1, f2, fl, loc) -> 
    let l1,f1 = elim_exists_with_fresh_vars f1 in
    let l2,f2 = elim_exists_with_fresh_vars f2 in
    l1@l2, Or (f1, f2, fl, loc)
  | Not (f1, fl, loc) -> 
    let l1,f1 = elim_exists_with_fresh_vars f1 in
    l1,Not (f1, fl, loc)
  | Forall _ -> [],f  (* Not skolemization: All x. Ex y. P(x, y) -> All x. P(x, f(x)) *)

let elim_exists_with_fresh_vars f =
  let pr = !print_formula in
  Debug.no_1 "elim_exists_with_fresh_vars" pr (pr_pair !print_svl pr) elim_exists_with_fresh_vars f 

(* Slicing: Normalize LHS to DNF *)
let rec dist_not_inwards f =
  match f with
  | Not (f1, fl, _) ->
    (match f1 with
     | BForm _ -> f
     | And (f2, f3, loc) -> Or (dist_not_inwards (Not (f2, fl, no_pos)), dist_not_inwards (Not (f3, fl, no_pos)), fl, loc)
     | AndList b -> report_error no_pos "unexpected AndList list"
     | Or (f2, f3, _, loc) -> And (dist_not_inwards (Not (f2, fl, no_pos)), dist_not_inwards (Not (f3, fl, no_pos)), loc)
     | Not (f2, _, _) -> dist_not_inwards f2
     | Forall (sv, f2, fl, loc) -> Exists (sv, dist_not_inwards (Not (f2, fl, no_pos)), fl, loc)
     | Exists (sv, f2, fl, loc) -> Forall (sv, dist_not_inwards (Not (f2, fl, no_pos)), fl, loc))
  | BForm _ -> f
  | And (f1, f2, loc) -> And (dist_not_inwards f1, dist_not_inwards f2, loc)
  | AndList b-> AndList (map_l_snd dist_not_inwards b)
  | Or (f1, f2, fl, loc) -> Or (dist_not_inwards f1, dist_not_inwards f2, fl, loc)
  | Forall (sv, f1, fl, loc) -> Forall (sv, dist_not_inwards f1, fl, loc)
  | Exists (sv, f1, fl, loc) -> Exists (sv, dist_not_inwards f1, fl, loc)

let rec standardize_vars f =
  match f with
  | BForm _ -> f
  | And (f1, f2, loc) -> And (standardize_vars f1, standardize_vars f2, loc)
  | AndList b -> AndList (map_l_snd standardize_vars b)
  | Or (f1, f2, fl, loc) -> Or (standardize_vars f1, standardize_vars f2, fl, loc)
  | Not (f1, fl, loc) -> Not (standardize_vars f1, fl, loc)
  | Exists (sv, f1, fl, loc) ->
    let SpecVar (t, i, p) = sv in
    let nf1 = subst [sv, SpecVar (t, fresh_any_name i, p)] f1 in
    Exists (sv, nf1, fl, loc)
  | Forall (sv, f1, fl, loc) ->
    let SpecVar (t, i, p) = sv in
    let nf1 = subst [sv, SpecVar (t, fresh_any_name i, p)] f1 in
    Forall (sv, nf1, fl, loc)

let rec dist_and_over_or f =
  match f with
  | BForm _ -> f
  | And (f1, f2, _) ->
    let nf1 = dist_and_over_or f1 in
    let nf2 = dist_and_over_or f2 in
    (match nf1 with
     | Or (f11, f12, lbl, _) ->
       let nf11 = And (f11, nf2, no_pos) in
       let nf12 = And (f12, nf2, no_pos) in
       Or (dist_and_over_or nf11, dist_and_over_or nf12, lbl, no_pos)
     | _ ->
       (match nf2 with
        | Or (f21, f22, lbl, _) ->
          let nf21 = And (nf1, f21, no_pos) in
          let nf22 = And (nf1, f22, no_pos) in
          Or (dist_and_over_or nf21, dist_and_over_or nf22, lbl, no_pos)
        | _ -> f))
  | AndList b -> AndList (map_l_snd dist_and_over_or b)
  | Or (f1, f2, fl, loc) ->
    let nf1 = dist_and_over_or f1 in
    let nf2 = dist_and_over_or f2 in
    Or (nf1, nf2, fl, loc)
  | Not (f, fl, loc) -> Not (dist_and_over_or f, fl, loc)
  | Forall (sv, f, fl, loc) -> Forall (sv, dist_and_over_or f, fl, loc)
  | Exists (sv, f, fl, loc) -> Exists (sv, dist_and_over_or f, fl, loc)

let trans_dnf f =
  let f = dist_not_inwards f in
  let () = x_tinfo_hp (add_str "before simplify" !print_formula) f no_pos in
  let f = !simplify f in
  let () = x_tinfo_hp (add_str "after simplify" !print_formula) f no_pos in
  let lex,f = x_add_1 elim_exists_with_fresh_vars f in
  let () = x_tinfo_hp (add_str "after elim" !print_formula) f no_pos in
  let f = dist_and_over_or f in
  lex,f

let rec dnf_to_list f =
  let lex,dnf_f = trans_dnf f in
  match dnf_f with
  | Or (f1, f2, _, _) ->
    let lex1,l_f1 = dnf_to_list f1 in
    let lex2,l_f2 = dnf_to_list f2 in
    lex@lex1@lex2, l_f1 @ l_f2
  | _ -> lex,[dnf_f]

let dnf_to_list f = Debug.no_1 "dnf_to_list" !print_formula (pr_pair !print_svl (pr_list !print_formula)) dnf_to_list f
   (*
let rec partition_dnf_lhs f =
  match f with
	| BForm (bf, _) -> [[bf]]
	| Forall _
	| Exists _
	| Not _ -> report_error no_pos "do not allow Forall, Exists, Not"
	| Or (f1, f2, _, _) -> (partition_dnf_lhs f1) @ (partition_dnf_lhs f2)
	| And (f1, f2, _) -> [List.flatten ((partition_dnf_lhs f1) @ (partition_dnf_lhs f2))]
	| AndList b -> fold_l_snd partition_dnf_lhs b*)

let find_relevant_constraints bfl fv =
  let parts = group_related_vars bfl in
  List.filter (fun (svl,lkl,bfl) -> (*fst (check_dept fv (svl, lkl))*) true) parts


(* An Hoa : REMOVE PRIMITIVE CONSTRAINTS IF should_elim EVALUATE TO true *)
let remove_primitive should_elim e =
  let rec elim_formula f = match f with
    | BForm ((bf, _) , _) -> if (should_elim bf) then None else Some f
    | Or (f1, f2, x, y) -> 
      let nf1 = elim_formula f1 in
      let nf2 = elim_formula f2 in
      (match (nf1,nf2) with
       | (None,None) -> None
       | (None,Some _) -> nf2
       | (Some _,None) -> nf1
       | (Some nff1, Some nff2) -> Some (Or (nff1, nff2, x, y)))
    | And (f1, f2, x) -> 			
      let nf1 = elim_formula f1 in
      let nf2 = elim_formula f2 in
      (match (nf1,nf2) with
       | (None,None) -> None
       | (None,Some _) -> nf2
       | (Some _,None) -> nf1
       | (Some nff1, Some nff2) -> Some (And (nff1, nff2, x)))
    | AndList b -> Some (AndList (map_l_snd (fun c-> match elim_formula c with | None -> mkTrue no_pos | Some c-> c)b))
    | Forall (sv, f1, fl, loc) -> 
      let nf = elim_formula f1 in
      (match nf with
       | None -> None
       | Some nf1 -> Some (Forall (sv, nf1, fl, loc)))
    | Exists (sv, f1, fl, loc) -> 
      let nf = elim_formula f1 in
      (match nf with
       | None -> None
       | Some nf1 -> Some (Exists (sv, nf1, fl, loc)))
    | Not (f1, fl, loc) -> 
      let nf = elim_formula f1 in
      (match nf with
       | None -> None
       | Some nf1 -> Some (Not (nf1, fl, loc))) in
  let r = elim_formula e in
  match r with
  | None -> mkTrue no_pos
  | Some f -> f


(** An Hoa : SIMPLIFY PURE FORMULAE **)
(* An Hoa : remove redundant identity constraints. *)
let rec remove_redundant_constraints (f : formula) : formula = match f with
  | BForm ((b,a),l) -> BForm ((remove_redundant_constraints_b b,a),l)
  | And (f1,f2,l) -> 
    let g1 = remove_redundant_constraints f1 in
    let g2 = remove_redundant_constraints f2 in
    mkAnd g1 g2 l
  | AndList b -> AndList (map_l_snd remove_redundant_constraints b)
  | Or (f1,f2,l,p) ->
    let g1 = remove_redundant_constraints f1 in
    let g2 = remove_redundant_constraints f2 in
    mkOr g1 g2 l p
  | _ -> f

and remove_redundant_constraints_b f = match f with  
  | Eq (e1,e2,l) -> 
    let r = eqExp_f eq_spec_var e1 e2 in 
    if r then BConst (true,no_pos) else f
  | _ -> f

(* Reference to function to solve equations in module Redlog. To be initialized in redlog.ml *)
let solve_equations = ref (fun (eqns : (exp * exp) list) (bv : spec_var list) -> (([],[]) : (((spec_var * spec_var) list) * ((spec_var * string) list))))

(* An Hoa : Reduce the formula by removing redundant atomic formulas and variables given the list of "important" variables *)
let rec reduce_pure (f : formula) (bv : spec_var list) =
  (* Split f into collections of conjuction *)
  let c = split_conjunctions f in
  (* Pick out the term that are atomic *)
  let bf, uf = List.partition (fun x -> match x with | BForm _ -> true | _ -> false) c in 
  let bf = List.fold_left  (fun a x -> 
      match x with | BForm ((y,_),_) -> y::a
                   | _ -> a) [] bf in
  (* Pick out equality from all atomic *)
  let ebf, obf = List.partition (fun x -> match x with | Eq _ -> true | _ -> false) bf in
  let ebf = List.map (fun x -> match x with | Eq (e1,e2,p) -> (e1,e2,p) | _ -> failwith "Eq fail!") ebf in
  let eqns = List.map (fun (e1,e2,p) -> (e1,e2)) ebf in
  (* Solve the equation to find the substitution *)
  let sst,strrep = !solve_equations eqns bv in
  (sst,strrep)

let compute_instantiations_x pure_f v_of_int avail_v =
  let ldisj = list_of_conjs pure_f in
  let leqs = List.fold_left (fun a c-> match c with | BForm ((Eq(e1,e2,_),_),_) ->  (e1,e2)::a |_-> a) [] ldisj in

  let v_in v e = List.exists (eq_spec_var v) (afv e) in

  let expose_one_var e v rhs_e :exp = 
    let rec check_in_one (e1:exp) (e2:exp) (r1:exp) (r2:exp) :exp = 
      if v_in v e1 then 
        if v_in v e2 then raise Not_found 
        else helper e1 r1 
      else 
      if v_in v e2 then helper e2 r2 
      else failwith ("expecting var"^ (!print_sv v) ) 

    and helper (e:exp) (rhs_e:exp) :exp = match e with 
      | IConst _
      | FConst _
      | InfConst _ 
      | NegInfConst _
      | AConst _
      | Level _
      | Tsconst _ 
      | Null _ -> failwith ("expecting var"^ (!print_sv v) )
      | Var (v1,_) -> if (eq_spec_var v1 v) then rhs_e else failwith ("expecting var"^ (!print_sv v))
      | Bptriple _ -> failwith ("not expecting Bptriple, expecting var"^ (!print_sv v) )
      | Tup2 ((e1,e2),p) -> Tup2 ((helper e1 rhs_e,helper e2 rhs_e),p)
      | Add (e1,e2,p) -> check_in_one e1 e2 (Subtract (rhs_e,e2,p)) (Subtract (rhs_e,e1,p))
      | Subtract (e1,e2,p) -> check_in_one e1 e2 (Add (rhs_e,e2,p)) (Add (rhs_e,e1,p))
      | Mult (e1,e2,p) -> check_in_one e1 e2 (Div (rhs_e,e2,p)) (Div (rhs_e,e1,p))
      | Div (e1,e2,p) -> check_in_one e1 e2 (Mult (rhs_e,e2,p)) (Mult (rhs_e,e1,p))
      (* expressions that can not be transformed *)
      | TypeCast _
      | Min _ | Max _ | List _ | ListCons _ | ListHead _ | ListTail _ | ListLength _ | ListAppend _ | ListReverse _ |ArrayAt _ 
      | BagDiff _ | BagIntersect _ | Bag _ | BagUnion _ | Func _ | Template _ -> raise Not_found in
    helper e rhs_e in

  let prep_eq (acc:(spec_var*exp) list) v e1 e2 = 
    try 
      if v_in v e1 then
        if v_in v e2 then acc
        else ((v,expose_one_var e1 v e2)::acc)
      else 
      if v_in v e2 then ((v,expose_one_var e2 v e1)::acc)
      else acc
    with 
    | Not_found -> acc in

  let rec compute_one l_stk l_eqs v = 
    if List.exists (eq_spec_var v) l_stk then []
    else
      let l_eq_of_int =  List.fold_left (fun a (e1,e2) -> 
          let l = remove_dups_svl (afv e1 @ afv e2) in
          if List.exists (eq_spec_var v) l then (l,(e1,e2))::a
          else a) [] l_eqs in

      let l = List.fold_left (fun a (l_fv,(e1,e2))->
          let rem_vars = Gen.BList.difference_eq eq_spec_var l_fv (v::avail_v) in
          if rem_vars == [] then prep_eq a v e1 e2
          else 
            try
              let l_subs = List.fold_left (fun a r_v -> match compute_one (v::l_stk) l_eqs r_v with 
                  | [] -> raise Not_found
                  | h::_ -> h::a) [] rem_vars in
              prep_eq a v (a_apply_par_term l_subs e1) (a_apply_par_term l_subs e2) 
            with | Not_found -> a
        ) [] l_eq_of_int in
      match l with 
      |[] -> []
      |h::t-> [h] in
  let l_r = List.concat (List.map (compute_one [] leqs) v_of_int) in
  List.map (fun (v,e) -> (v,BForm ((Eq (Var (v,no_pos),e,no_pos), None),None))) l_r 


let compute_instantiations pure_f v_of_int avail_v =
  let pr1 = !print_formula in
  let pr2 = !print_svl in
  let pr3 = pr_list (pr_pair !print_sv !print_formula) in
  Debug.no_3  "compute_instantiations" pr1 pr2 pr2 pr3 (fun _ _ _ -> compute_instantiations_x pure_f v_of_int avail_v) pure_f v_of_int avail_v

let add_ann_constraints vrs f = 
  if not(!Globals.allow_field_ann) then f 
  else
    let rec helper vrs f = 
      match vrs with
      | v :: r -> 
        let c1 = BForm((Lte(IConst( (int_of_heap_ann Mutable), no_pos), Var(v,no_pos), no_pos), None), None) in
        let c2 = BForm((Lte(Var(v,no_pos), IConst(( (int_of_heap_ann Accs)), no_pos), no_pos), None), None) in 
        (* let c2 = BForm((Lte(Var(v,no_pos), IConst(( (int_of_heap_ann Lend)), no_pos), no_pos), None), None) in  *)
        let c12 = mkAnd c1 c2 no_pos in
        let rf = helper r f in
        mkAnd c12  rf no_pos
      | [] -> f
    in helper vrs f

let add_ann_constraints vrs f =
  let p1 = !print_formula in
  Debug.no_2 "add_ann_constraints" !print_svl p1 p1  add_ann_constraints vrs f

type infer_state = 
  { 
    infer_state_vars : spec_var list; (* [] if no inference *)
    infer_state_rel : (formula * formula) Gen.stack (* output *)
  }

let create_infer_state vs =
  (*  let prf = !print_formula in*)
  (*  let pr (lhs,rhs) = (prf lhs)^" --> "^(prf rhs) in *)
  { 
    infer_state_vars = vs;
    infer_state_rel = new Gen.stack;
  }

let no_infer_state = create_infer_state []

(* any inference for is *)
let no_infer (is:infer_state) = is.infer_state_vars ==[]

(* is v an infer var of is *)
let mem_infer_var (v:spec_var) (is:infer_state) 
  = mem v is.infer_state_vars

(* add lhs -> rhs to infer state is *)
let add_rel_to_infer_state (lhs:formula) (rhs:formula) (is:infer_state) 
  = is.infer_state_rel # push (lhs,rhs)

(* checks if formula is of form var = annotation constant *)
let is_eq_with_aconst (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (_,_), AConst _, _),_) 
     | (Eq (AConst _, Var (_,_), _),_) -> true
     | _ ->  false)
  | _ ->  false

(* checks if formula is of form var = annotation constant *)
let get_aconst (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (_,_), AConst (ann,_), _),_) 
     | (Eq (AConst (ann,_), Var (_,_), _),_) -> Some ann
     | _ -> None)
  | _ -> None

let is_eq_const (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (_,_), IConst _, _),_)
     | (Eq (IConst _, Var (_,_), _),_) -> true
     | _ -> false)
  | _ -> false

let is_eq_exp (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq _,_) -> true
     | _ -> false)
  | _ -> false

let is_eq_exp_ptrs svl (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (sv1,_), Var (sv2, _),_ ),_) -> is_node_typ sv1 && is_node_typ sv2 &&
                                                (mem_svl sv1 svl || mem_svl sv2 svl)
     | _ -> false)
  | _ -> false

let is_eq_null_exp (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (sv1,sv2,_),_) ->
       begin
         match sv1,sv2 with
         | Var _, Null _ -> true
         | Null _, Var _ -> true
         | _ -> false
       end
     | _ -> false)
  | _ -> false

let is_eq_null_exp_in_list svl (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (sv1,sv2,_),_) ->
       begin
         match sv1,sv2 with
         | Var (sv,_), Null _
         | Null _, Var (sv,_) -> mem_svl sv svl
         | _ -> false
       end
     | _ -> false)
  | _ -> false

let get_null_formula p=
  let ps = list_of_conjs p in
  let ps1 = List.filter is_eq_null_exp ps in
  conj_of_list ps1 (pos_of_formula p)

let is_eq_between_vars (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (_,_), Var (_,_), _),_) -> true
     | _ -> false)
  | _ -> false

let is_eq_between_no_bag_vars (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Var (v,_), Var (_,_), _),_) -> if (is_bag_typ v) then false else true
     | _ -> false)
  | _ -> false

let rec is_neq_exp (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Neq _,_) -> true
     | _ -> false)
  | Exists (_,p1,_,_) -> is_neq_exp p1
  | _ -> false
  
let get_neqs_new p=
  let get_neq acc p = match p with
    | BForm (bf,_) -> (match bf with
        | (Neq (Var (sv1,_), Var (sv2,_), _),_) -> acc@[(sv1,sv2)]
        | _ -> acc
      )
    | _ -> acc
  in
  let ps = list_of_conjs p in
  List.fold_left get_neq [] ps

let get_neqs_ptrs_form p=
  let combine_neq acc p = match p with
    | BForm (bf,_) -> (match bf with
        | (Neq (Var (sv1,_), Var (sv2,_),pos),_) ->
          if is_node_typ sv1 && is_node_typ sv2 then mkAnd acc p pos
          else acc
        | _ -> acc
      )
    | _ -> acc
  in
  let ps = list_of_conjs p in
  List.fold_left combine_neq (mkTrue no_pos) ps

let rec is_eq_neq_exp (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Neq _,_) -> true
     | (Eq _,_) -> true
     | _ -> false)
  | Exists (_,p1,_,_) -> is_eq_neq_exp p1
  | _ -> false


let is_neq_null_exp_x (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Neq (sv1,sv2,_),_) ->
       begin
         match sv1,sv2 with
         | Var _, Null _ -> true
         | Null _, Var _ -> true
         | _ -> false
       end
     | _ -> false)
  | _ -> false

let is_neq_null_exp (f:formula)=
  let pr1 = !print_formula in
  Debug.no_1 "is_neq_null_exp" pr1 string_of_bool
    (fun _ -> is_neq_null_exp_x f) f

let rec contains_neq (f:formula) : bool =  match f with
  | BForm (b1,_) -> (is_neq_exp f) || (is_neq_null_exp f)
  | Or (f1,f2,_,_)  
  | And (f1,f2, _) -> (contains_neq f1) || (contains_neq f2) 
  | Not(f1,_,_)
  | Forall (_ ,f1,_,_) 
  | Exists (_ ,f1,_,_) -> (contains_neq f1)  
  | AndList l -> exists_l_snd contains_exists l


let neg_eq_neq_x f0=
  let rec helper f= match f with
    | BForm (bf,a) ->
      (match bf with
       | (Neq (sv1,sv2,b),c) ->
         let sv1,sv2 = if is_null sv1 then (sv2, sv1) else (sv1,sv2) in
         BForm ((Eq (sv1, sv2, b), c), a)
       | (Eq (sv1,sv2,b),c) ->
         let sv1,sv2 = if is_null sv1 then (sv2, sv1) else (sv1,sv2) in
         BForm ((Neq (sv1, sv2, b), c), a)
       | _ -> f)
    | Exists (a, p, c,l) ->
      Forall (a, helper p, c,l)
    | Forall (a, p, c,l) ->
      Exists (a, helper p, c,l)
    | _ -> f
  in
  helper f0

let neg_eq_neq f0=
  let pr1 = !print_formula in
  Debug.no_1 "neg_eq_neq" pr1 pr1
    (fun _ -> neg_eq_neq_x f0) f0

(*neg(x!=y) == x=y; neg(x!=null) === x=null*)
let rec neg_neq_x f=
  match f with
  | BForm (bf,a) ->
    (match bf with
     | (Neq (sv1,sv2,b),c) ->
       let sv1,sv2 = if is_null sv1 then (sv2, sv1) else (sv1,sv2) in
       BForm ((Eq (sv1, sv2, b), c), a)
     | _ -> f)
  | Exists (a, p, c,l) ->
    Forall (a, neg_neq_x p, c,l)
  | _ -> f

let neg_neq p=
  let pr1 = !print_formula in
  Debug.no_1 "neg_neq" pr1 pr1
    (fun _ -> neg_neq_x p) p

let map_f f0 fnc_bf fnc_comb=
  let rec recf f= match f with
    | BForm (b,_)-> fnc_bf b
    | And (b1,b2,_) -> fnc_comb (recf b1) (recf b2)
    | AndList b -> List.fold_left (fun svl (_,c)->
          let svl1 = recf c in
          fnc_comb svl svl1) [] b
    | Or (b1,b2,_,_) -> fnc_comb (recf b1) (recf b2)
    | Not (b,_,_)-> recf b
    | Forall (_,f,_,_) -> recf f
    | Exists (_,f,_,_) -> recf f
  in
  recf f0


let rec get_neq_null_svl_x (f:formula) =
  let helper (bf:b_formula) =
    match bf with
    | (Neq (sv1,sv2,_),_) -> begin
        match sv1,sv2 with
        | Var (v,_), Null _ -> [v]
        | Null _, Var (v,_) -> [v]
        | _ -> []
      end
    | _ -> []
  in
  (* match f with *)
  (* | BForm (b,_)-> helper b *)
  (* | And (b1,b2,_) -> (get_neq_null_svl_x b1)@(get_neq_null_svl_x b2) *)
  (* | AndList b -> List.fold_left (fun svl (_,c)-> *)
  (*     let svl1 = get_neq_null_svl_x c in *)
  (*     svl@svl1) [] b *)
  (* | Or (b1,b2,_,_) -> (get_neq_null_svl_x b1)@(get_neq_null_svl_x b2) *)
  (* | Not (b,_,_)-> get_neq_null_svl_x b *)
  (* | Forall (_,f,_,_) -> get_neq_null_svl_x f *)
  (* | Exists (_,f,_,_) -> get_neq_null_svl_x f *)
  map_f f helper (@)

let get_neq_null_svl (f:formula)=
  let pr1 = !print_formula in
  Debug.no_1 "get_neq_null_svl" pr1 !print_svl
    (fun _ -> get_neq_null_svl_x f) f

let rec get_eq_null_svl_x (f:formula) =
  let helper (bf:b_formula) =
    match bf with
    | (Eq (sv1,sv2,_),_) -> begin
        match sv1,sv2 with
        | Var (v,_), Null _ -> [v]
        | Null _, Var (v,_) -> [v]
        | _ -> []
      end
    | _ -> []
  in
  map_f f helper (@)

let get_eq_null_svl (f:formula)=
  let pr1 = !print_formula in
  Debug.no_1 "get_eq_null_svl" pr1 !print_svl
    (fun _ -> get_eq_null_svl_x f) f



let check_dang_or_null_exp_x root (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (esv1, esv2 ,_),_) ->
       begin
         match esv1,esv2 with
         | Var (sv1,_), Null _ ->
           if eq_spec_var sv1 root then
             (false,true)
           else (false,false)
         | Var (sv1,_), Var (sv2, _) ->
           (
             let b1 = eq_spec_var sv1 root in
             let b2 = eq_spec_var sv2 root in
             match b1,b2 with
             | true,true
             | false,false -> (false,false)
             | _ -> (true,false)
           )
         | Null _, Var (sv2,_) ->
           if eq_spec_var sv2 root then
             (false,true)
           else (false,false)
         | _ -> (false,false)
       end
     | _ -> (false,false)
    )
  | _ -> (false,false)



let check_dang_or_null_exp root (f:formula) =
  let pr1 = pr_pair string_of_bool string_of_bool in
  Debug.no_2 "check_dang_or_null_exp" !print_sv !print_formula pr1
    (fun _ _ -> check_dang_or_null_exp_x root f) root f

let is_beq_exp (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (_,BagUnion _,_),_) -> true
     | _ -> false)
  | _ -> false

let get_rank_dec_id_list (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Gt (Func (id1,_,_), Func (id2,_,_),_),_) -> [id1;id2]
     | (Lt (Func (id1,_,_), Func (id2,_,_),_),_) -> [id1;id2]
     | _ -> [])
  | _ -> []

let rec get_rank_dec_and_const_id_list (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Gt (Func (id1,_,_), Func (id2,_,_),_),_) -> [id1;id2]
     | (Lt (Func (id1,_,_), Func (id2,_,_),_),_) -> [id1;id2]
     | _ -> [])
  | And _ -> 
    List.concat (List.map (fun p -> get_rank_dec_and_const_id_list p) (list_of_conjs f))
  | _ -> []

let get_rank_const_id_list (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Eq (Func (id1,_,_), Func (id2,_,_),_),_) -> [id1;id2]
     | _ -> [])
  | _ -> []

let get_rank_bnd_id_list (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (Gte (Func (id,_,_), IConst (0,_),_),_) -> [id]
     | (Lte (IConst (0,_), Func (id,_,_),_),_) -> [id]
     | _ -> [])
  | _ -> []

let is_Rank (f:formula) = match f with
  | BForm _ -> (get_rank_dec_id_list f) != [] || (get_rank_bnd_id_list f) != []
  | _ -> false

let is_Rank_Dec (f:formula) = match f with
  | BForm _ -> (get_rank_dec_id_list f) != []
  | _ -> false

let is_Rank_Const (f:formula) = match f with
  | BForm _ -> (get_rank_const_id_list f) != []
  | _ -> false

let rec get_Rank pf = match pf with
  | BForm (bf,_) -> if is_Rank pf then [pf] else []
  | And (f1,f2,_) -> get_Rank f1 @ get_Rank f2
  | AndList b -> fold_l_snd get_Rank b
  | Or (f1,f2,_,_) -> get_Rank f1 @ get_Rank f2
  | Not (f,_,_) -> get_Rank f
  | Forall (_,f,_,_) -> get_Rank f
  | Exists (_,f,_,_) -> get_Rank f

let term_id = 1
let loop_id = 2
let mayLoop_id = 3 
let termErr_id = 4

(* let sid_of_term_ann ann =  *)
(*   match ann with *)
(*   | Term -> string_of_int term_id *)
(*   | Loop _ -> string_of_int loop_id *)
(*   | MayLoop _ -> string_of_int mayLoop_id *)
(*   | Fail _ -> string_of_int termErr_id *)
(*   | TermU uid -> uid.tu_sid *)
(*   | TermR uid -> uid.tu_sid *)

let id_of_term_ann ann = 
  match ann with
  | Term -> term_id
  | Loop _ -> loop_id
  | MayLoop _ -> mayLoop_id
  | Fail _ -> termErr_id
  | TermU uid -> uid.tu_id
  | TermR uid -> uid.tu_id

let sid_of_term_ann ann = 
  (* string_of_int (id_of_term_ann ann) *)
  match ann with 
  | TermU uid | TermR uid -> uid.tu_sid
  | _ -> ""

(* = match f with *)
(*   | BForm (bf,_) -> *)
(*         (match bf with *)
(*           | (RelForm(id,_,_),_) -> Some id *)
(*           | (XPure(_),_) -> failwith "XPure" *)
(*           | (LexVar li,_) -> *)
(*                 let la = li.lex_ann in *)
(*                 let id = sid_of_term_ann la in *)
(*                  Some (mk_spec_var id) *)
(*           | (VarPerm (_),_) -> failwith "VarPerm" *)
(*           | _ -> None) *)
(*   | _ -> None *)

let get_relargs_opt (f:formula)
  = match f with
  | BForm (bf,_) ->
    (match bf with
     | (RelForm(id,eargs,_),_) -> Some (id, (List.fold_left List.append [] (List.map afv eargs)))
     | _ -> None)
  | _ -> None


let is_trivial_rel (rel_c, lhs, rhs)=
  let l_ohp = get_relargs_opt lhs in
  let r_ohp = get_relargs_opt rhs in
  match l_ohp,r_ohp with
    | Some (hp1,largs), Some (hp2, rargs) -> if eq_spec_var hp1 hp2 then
        eq_spec_var_order_list largs rargs
      else false
    | _ -> false

let is_trivial_rel rel_f=
  let pr = print_lhs_rhs in
  Debug.no_1 "is_trivial_rel" pr string_of_bool
      (fun _ -> is_trivial_rel rel_f) rel_f


let get_list_rel_args_x (f0:formula) =
  let rec helper f=
    match f with
    | BForm (bf,_) ->
      (match bf with
       | (RelForm(id,eargs,_),_) -> [(id, (List.fold_left List.append [] (List.map afv eargs)))]
       | _ -> [])
    | And (f1,f2,_) -> (helper f1)@(helper f2)
    | Exists (_,p1,_,_) -> helper p1
    | _ -> []
  in
  helper f0

let get_list_rel_args (f0:formula) =
  let pr1 = pr_list (pr_pair !print_sv !print_svl) in
  Debug.no_1 "get_list_rel_args" !print_formula pr1
    (fun _ ->  get_list_rel_args_x f0) f0

let get_rel_id_list (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (RelForm(id,_,_),_) -> [id]
     | (XPure(_),_) -> failwith "XPure"
     | (LexVar li,_) ->
       let la = li.lex_ann in
       let id = sid_of_term_ann la in
       [mk_spec_var id]
     (* | (VarPerm (_),_) -> failwith "VarPerm" *)
     | _ -> [])
  | _ -> []
;;

let get_rel_id_list (f:formula) =
  let f_b bf =
    match bf with
    | (RelForm (id,_,_),_) -> Some [id]
    | _ -> Some []
  in
  fold_formula f (nonef, f_b, nonef) List.concat
;;

let get_rel_id (f:formula)
  = let lst = get_rel_id_list f in
  match lst with
  | [] -> None
  | id::_ -> Some id

let get_rel_id (f:formula) =
  Debug.no_1 "get_rel_id" !print_formula (pr_opt !print_sv) get_rel_id f 

(* let mk_varperm_p typ ls pos =     *)
(*   if (ls==[]) then (mkTrue_p pos) *)
(*   else                            *)
(*   (VarPerm (typ,ls,pos))          *)

(* let mk_varperm typ ls pos =           *)
(*   let pf = mk_varperm_p typ ls pos in *)
(*   (BForm ((pf,None),None))            *)

(* let mk_varperm_zero ls pos =          *)
(*   mk_varperm VP_Zero ls pos           *)

(* let mk_varperm_full ls pos =          *)
(*   mk_varperm VP_Full ls pos           *)

(* formula -> formula_w_varperm * formula_wo_varperm*)
(* combine VarPerm formulas into 4 types*)
(* let normalize_varperm_x (f:formula) : formula =                                                                   *)
(*   let ls = split_conjunctions f in                                                                                *)
(*   let lsf1,lsf2 = List.partition (is_varperm) ls in                                                               *)
(*   (* let () = print_endline ("normalize_varperm:"  *)                                                              *)
(*   (*                        ^ "\n ### |lsf1| = " ^ (string_of_int (List.length lsf1)) *)                          *)
(*   (*                        ^ "\n ### |lsf2| = " ^ (string_of_int (List.length lsf2))) in *)                      *)
(*   (*zero, full , value *)                                                                                         *)
(*   let rec helper ls =                                                                                             *)
(*     match ls with                                                                                                 *)
(*       | [] -> [],[],[] (*list of vars*)                                                                           *)
(*       | x::xs ->                                                                                                  *)
(*           let ls1,ls2,ls3 = helper xs in                                                                          *)
(*           (match x with                                                                                           *)
(*             | BForm ((pf,_),_) ->                                                                                 *)
(*                ( match pf with                                                                                    *)
(*                   | VarPerm (ct,xs,_) ->                                                                          *)
(*                       (match ct with                                                                              *)
(*                         | VP_Zero ->                                                                              *)
(*                             (remove_dups_svl (xs@ls1)),ls2,ls3                                                    *)
(*                         | VP_Full ->                                                                              *)
(*                             ls1,(remove_dups_svl (xs@ls2)),ls3                                                    *)
(*                         | VP_Value ->                                                                             *)
(*                             ls1,ls2,(remove_dups_svl (xs@ls3))                                                    *)
(*                         (* TODO: Norm VarPerm for @lend and @frac *)                                              *)
(*                         | VP_Lend -> [], [], []                                                                   *)
(*                         | VP_Frac _ -> [], [], []                                                                *)
(*                       )                                                                                           *)
(*                   | _ -> Error.report_error {Error.error_loc = no_pos;                                            *)
(*                                              Error.error_text = "normalize_varperm: VarPerm not found";}          *)
(*                )                                                                                                  *)
(*             | _ -> Error.report_error {Error.error_loc = no_pos;                                                  *)
(*                                              Error.error_text = "normalize_varperm: BForm of VarPerm not found";} *)
(*           )                                                                                                       *)
(*   in                                                                                                              *)
(*   let ls1,ls2,ls3 = helper lsf1 in (*find out 4 types of var permission*)                                         *)
(*   let func typ ls =                                                                                               *)
(*     (match ls with                                                                                                *)
(*       | [] -> mkTrue no_pos                                                                                       *)
(*       | _ -> mk_varperm typ ls no_pos)                                                                            *)
(*   in                                                                                                              *)
(*   let f1 = func VP_Zero ls1 in                                                                                    *)
(*   let f2 = func VP_Full ls2 in                                                                                    *)
(*   let f3 = func VP_Value ls3 in                                                                                   *)
(*   let lsf1 = [f1;f2;f3] in                                                                                        *)
(*   let new_f = join_conjunctions (lsf1@lsf2) in                                                                    *)
(*   new_f                                                                                                           *)

(* let normalize_varperm (f:formula) : formula =                                                                     *)
(*   Debug.no_1 "normalize_varperm"                                                                                  *)
(*       !print_formula !print_formula                                                                               *)
(*       normalize_varperm_x f                                                                                       *)
(* let filter_varperm (f:formula) : formula * formula =  *)
(*   let ls = split_conjunctions f in *)
(*   let ls1,ls2 = List.partition (is_varperm) ls in *)
(*   let f1 = join_conjunctions ls1 in *)
(*   let f2 = join_conjunctions ls2 in *)

(* let filter_varperm (f:formula) : (formula list * formula) = *)
(*   let ls = split_conjunctions f in                          *)
(*   let lsf1,lsf2 = List.partition (is_varperm) ls in         *)
(*   (lsf1, join_conjunctions lsf2)                            *)

let is_hole_spec_var (x:spec_var) =
  (match x with
   | SpecVar (_,vn,_) -> if (vn.[0] = '#') then true else false)

(*Eq, Lt, Lte, Gt, Gte*)
let remove_dupl_conj_list (cnjlist:formula list):formula list =
  (* let fct e1 e2 = *)
  (*   (is_dupl_conj_eq e1 e2) *)
  (*   || (is_dupl_conj_lt e1 e2) *)
  (*   || (is_dupl_conj_lte e1 e2) *)
  (*   || (is_dupl_conj_gt e1 e2) *)
  (*   || (is_dupl_conj_gte e1 e2) *)
  (* in *)
  Gen.BList.remove_dups_eq (equalFormula_f eq_spec_var) cnjlist
(* Gen.BList.remove_dups_eq fct cnjlist *)

(*Eq, Lt, Lte, Gt, Gte*)
let remove_dupl_conj_opt_list (cnjlist:formula option list):formula option list =
  Gen.BList.remove_dups_eq (fun opt1 opt2 -> 
      match (opt1, opt2) with 
      | (None, None) 
      | (Some _, None)
      | (None, Some _)  -> false
      | (Some f1, Some f2) -> equalFormula_f eq_spec_var f1 f2) cnjlist

(*Eq, Lt, Lte, Gt, Gte*)
let remove_dupl_conj_pure (p:formula) =
  let ps = split_conjunctions p in
  let ps1 = remove_dupl_conj_list ps in
  let ps2 = join_conjunctions ps1 in 
  ps2


let get_rel_args (f:formula) = match f with
  | BForm (bf,_) ->
    (match bf with
     | (RelForm(_,eargs,_),_) -> List.concat (List.map afv eargs)
     | _ -> [])
  | _ -> []

let is_rel_in_vars (vl:spec_var list) (f:formula) =
  (* let () = x_tinfo_hp (add_str "2formula" !print_formula) f no_pos in *)
  match (x_add_1 get_rel_id f) with
  | Some n ->
    if mem n vl then true else false
  | _ ->
    (* let () = Debug.tinfo_pprint "2None" no_pos in *)
    false

let is_rel_in_vars (vl:spec_var list) (f:formula) =
  let pr_svl = !print_svl in
  Debug.no_2 "is_rel_in_vars" pr_svl !print_formula string_of_bool
    is_rel_in_vars vl f


let is_RelForm (f:formula) = match f with
  | BForm((RelForm _,_),_) -> true
  | _ -> false

let rec get_RelForm pf = match pf with
  | BForm (bf,_) -> if is_RelForm pf then [pf] else []
  | And (f1,f2,_) -> get_RelForm f1 @ get_RelForm f2
  | AndList b-> fold_l_snd get_RelForm b
  | Or (f1,f2,_,_) -> get_RelForm f1 @ get_RelForm f2
  | Not (f,_,_) -> get_RelForm f
  | Forall (_,f,_,_) -> get_RelForm f
  | Exists (_,f,_,_) -> get_RelForm f

let get_RelForm_arg_list_with_name pf name =
  let rel_form_list = get_RelForm pf in
  List.fold_left 
    (fun r rel -> 
       match rel with
       | BForm ((RelForm (sv,args,_),_),_) ->
         if (get_unprime sv)=name
         then 
           (List.concat(List.map (fun e -> match e with
             | Var(sv,_) -> [sv]
             | _ -> []) args))@r
         else
           r
       | _ -> failwith "get_RelForm_arg_list_with_name: Invalid input"
    ) [] (get_RelForm pf)
;;
let rec get_Neg_RelForm pf = match pf with
  | BForm (bf,_) -> []
  | And (f1,f2,_) -> get_Neg_RelForm f1 @ get_Neg_RelForm f2
  | AndList b -> fold_l_snd get_Neg_RelForm b 
  | Or (f1,f2,_,_) -> get_Neg_RelForm f1 @ get_Neg_RelForm f2
  | Not (f,_,_) -> get_RelForm f
  | Forall (_,f,_,_) -> get_Neg_RelForm f
  | Exists (_,f,_,_) -> get_Neg_RelForm f

let assumption_filter (ante : formula) (conseq : formula) : (formula * formula) =
  if !filtering_flag (* && (not !allow_pred_spec) *) 
  then (filter_ante ante conseq, conseq)
  else (ante, conseq)

(* need unsat checking for disjunctive LHS *)
let assumption_filter_aggressive is_sat (ante : formula) (conseq : formula) : (formula * formula) =
  (* let () = print_string ("\naTpdispatcher.ml: filter") in *)
  if !filtering_flag (*&& (not !allow_pred_spec)*) then
    let ante_ls = List.filter is_sat (split_disjunctions ante) in
    if ante_ls==[] then (mkFalse no_pos,conseq)
    else
      let ante_ls = List.map (fun x -> filter_ante x conseq) ante_ls in
      let ante = join_disjunctions ante_ls in
      (ante, conseq)
  else (ante, conseq)

let filter_bag_constrain ante conseq =
  let conseq_ls = List.filter is_bag_constraint (split_disjunctions conseq) in
  if conseq_ls = [] then (mkFalse no_pos, mkTrue no_pos)
  else
    let ante = List.fold_left (fun an co -> filter_ante an co) ante conseq_ls in
    (ante,join_disjunctions conseq_ls)
;;

let filter_bag_constrain ante conseq =
  let pr = !print_formula in
  Debug.no_2 "filter_bag_constrain" pr pr (pr_pair pr pr) filter_bag_constrain ante conseq
;;

let assumption_filter_aggressive_incomplete (ante : formula) (conseq : formula) : (formula * formula) =
  assumption_filter_aggressive (fun x -> true) ante conseq 

let assumption_filter (ante : formula) (cons : formula) : (formula * formula) =
  let pr = !print_formula in
  Debug.no_2 "assumption_filter" pr pr (fun (l, _) -> pr l)
    assumption_filter ante cons

let rec has_func_exp (e: exp) : bool = match e with
  | Func _ -> true
  | _ -> false

and has_func_pf (pf: p_formula) : bool = match pf with
  | LexVar _ -> false
  | Lt (e1,e2,_)
  | Lte (e1,e2,_)
  | Gt (e1,e2,_)
  | Gte (e1,e2,_)
  | SubAnn (e1,e2,_)
  | Eq (e1,e2,_)
  | Neq (e1,e2,_)
  | BagSub (e1,e2,_)
  | ListIn (e1,e2,_)
  | ListNotIn (e1,e2,_)
  | ListAllN (e1,e2,_)
  | ListPerm (e1,e2,_) -> has_func_exp e1 || has_func_exp e2
  | EqMax (e1,e2,e3,_)
  | EqMin (e1,e2,e3,_) -> has_func_exp e1 || has_func_exp e2 || has_func_exp e3
  | BagIn (_,e,_)
  | BagNotIn (_,e,_) -> has_func_exp e
  | RelForm (_,_,_) -> false
  | _ -> false

and has_func (f:formula): bool = match f with 
  | BForm ((b,_),_) -> has_func_pf b
  | _ -> false

let is_lexvar_b_formula (bf: b_formula): bool =
  let b, _ = bf in 
  match b with
  | LexVar _ -> true
  | _ -> false 

let is_lexvar (f:formula): bool =
  match f with
  | BForm (bf, _) -> is_lexvar_b_formula bf
  | _ -> false

let is_cyclic_rel_x (f:formula) : bool =
  (match f with
   | BForm ((b,_),_) -> 
     (match b with
      | RelForm (SpecVar (_,id,_),_,pos) ->
        if (id = Globals.cyclic_name) then true
        else false
      | _ -> false)
   | _ -> false)

let is_cyclic_rel (f:formula) : bool =
  Debug.no_1 "is_cyclic_rel" !print_formula string_of_bool
    is_cyclic_rel_x f

let is_waitS_rel (f:formula) : bool =
  (match f with
   | BForm ((b,_),_) -> 
     (match b with
      | RelForm (SpecVar (_,id,_),_,pos) ->
        if (id = Globals.waitS_name) then true
        else false
      | _ -> false)
   | _ -> false)

let is_concrete_rel (f:formula) : bool =
  (match f with
   | BForm ((b,_),_) -> 
     (match b with
      | RelForm (SpecVar (_,id,_),_,pos) ->
        if (id = Globals.concrete_name) then true
        else false
      | _ -> false)
   | _ -> false)

let rec has_lexvar (f: formula) : bool =
  match f with
  | BForm _ -> is_lexvar f
  | And (f1, f2, _) -> (has_lexvar f1) || (has_lexvar f2)
  | AndList b -> exists_l_snd has_lexvar b
  | Or (f1, f2, _, _) -> (has_lexvar f1) && (has_lexvar f2)
  | Not (f, _, _) -> has_lexvar f
  | Forall (_, f, _, _)
  | Exists (_, f, _, _) -> has_lexvar f

let has_unknown_pre_lexvar (f: formula) =
  let f_b bf =
    let (pf, _) = bf in 
    match pf with
    | LexVar tinfo -> begin match tinfo.lex_ann with
        | TermU _ -> Some (true, true)
        | _ -> Some (true, false) end
    | _ -> None
  in
  let f_comb bl = 
    let has_lexvar, has_unknown = List.split bl in
    (List.exists idf has_lexvar, 
     List.exists idf has_unknown)
  in fold_formula f (nonef, f_b, nonef) f_comb

let has_known_pre_lexvar (f: formula) =
  let f_b bf =
    let (pf, _) = bf in 
    match pf with
    | LexVar tinfo -> begin match tinfo.lex_ann with
        | Term
        | Loop _ -> Some true
        | _ -> Some false end
    | _ -> None
  in
  let f_comb = List.exists idf in
  fold_formula f (nonef, f_b, nonef) f_comb

let collect_term_ann (f: formula) =
  let f_b bf =
    let (pf, _) = bf in 
    match pf with
    | LexVar tinfo -> Some [tinfo.lex_ann]
    | _ -> None
  in
  let f_comb = List.concat in
  fold_formula f (nonef, f_b, nonef) f_comb

let has_template_formula (f: formula): bool =
  let f_e e = match e with
    | Template _ -> Some true
    | _ -> None
  in
  let f_comb bl = List.exists (fun b -> b) bl in
  fold_formula f (nonef, nonef, f_e) f_comb

let has_template_b_formula (f: b_formula): bool =
  let f_e e = match e with
    | Template _ -> Some true
    | _ -> None
  in
  let f_comb bl = List.exists (fun b -> b) bl in
  fold_b_formula f (nonef, f_e) f_comb

let rec drop_formula (pr_w:p_formula -> formula option) pr_s (f:formula) : formula =
  let rec helper f = match f with
    | BForm ((b,_),_) -> 
      (match pr_w b with
       | None -> f
       | Some nf -> nf)
    | And (f1,f2,p) -> And (helper f1,helper f2,p)
    | AndList b -> AndList (map_l_snd helper b)
    | Or (f1,f2,l,p) -> Or (helper f1,helper f2,l,p)
    | Exists (vs,f,l,p) -> Exists (vs, helper f, l, p)
    | Not (f,l,p) -> Not (drop_formula pr_s pr_w f,l,p)
    | Forall (vs,f,l,p) -> Forall (vs, helper f, l, p)
  in helper f
;;

(* Drop some parts of the formula and return the dropped parts. The returned parts are of type p_formula. *)
let rec drop_formula_and_return (pr_w:p_formula -> formula option) pr_s (f:formula) =
  let rec helper f =
    match f with
    | BForm ((b,_),_) -> 
      (match pr_w b with
       | None -> (f,[])
       | Some nf -> (nf,[b]))
    | And (f1,f2,p) ->
       let (newf1,df1) = helper f1 in
       let (newf2,df2) = helper f2 in
       (And (newf1,newf2,p),df1@df2)
    | AndList b ->
       failwith "drop_formula_and_return: AndList TO BE IMPLEMENTED"
    | Or (f1,f2,l,p) ->
       let (newf1,df1) = helper f1 in
       let (newf2,df2) = helper f2 in
       (Or (newf1,newf2,l,p),df1@df2)
    | Exists (vs,f,l,p) ->
       let (newf,df) = helper f in
       (Exists (vs, newf, l, p),df)
    | Not (f,l,p) ->
       let (newf,df) = drop_formula_and_return pr_s pr_w f in
       (Not (newf,l,p),df)       
    | Forall (vs,f,l,p) ->
       let (newf,df) = helper f in
       (Forall (vs, newf, l, p),df)
  in
  helper f
;;
            
let drop_rel_formula_ops =
  let pr_weak b = match b with
    | RelForm (_,_,p) -> Some (mkTrue p)
    | _ -> None in
  let pr_strong b = match b with
    | RelForm (_,_,p) -> Some (mkFalse p)
    | _ -> None in
  (pr_weak,pr_strong)
;;

let drop_rel_formula_ops_with_filter filter =
  let pr_weak b = match b with
    | RelForm ((SpecVar (_,name,_)),_,p) when (not (List.exists (fun s -> (String.compare s name)=0) filter)) -> Some (mkTrue p)
    | _ -> None in
  let pr_strong b = match b with
    | RelForm ((SpecVar (_,name,_)),_,p) when (not (List.exists (fun s -> (String.compare s name)=0) filter)) -> Some (mkFalse p)
    | _ -> None in
  (pr_weak,pr_strong)
;;
  
let no_drop_ops =
  let pr x = None in
  (pr,pr)

let is_update_array_relation (r:string) = 
  (* match r with CP.SpecVar(_,r,_) -> *)
  let udrel = "update_array" in
  let udl = String.length udrel in
  (String.length r) >= udl && (String.sub r 0 udl) = udrel

let drop_complex_ops =
  let pr_weak b = match b with
    | LexVar t_info -> Some (mkTrue t_info.lex_loc)
    | RelForm (SpecVar (_, v, _),_,p) ->
      (*provers which can not handle relation => throw exception*)
      if (v="dom") || (v="amodr") || (is_update_array_relation v) then None
      else Some (mkTrue p)
    | _ -> if has_template_b_formula (b, None) 
      then Some (mkTrue (pos_of_b_formula (b, None))) else None in
  let pr_strong b = match b with
    | LexVar t_info -> ((*print_string "dropping strong1\n";*)Some (mkFalse t_info.lex_loc))
    | RelForm (SpecVar (_, v, _),_,p) ->
      (*provers which can not handle relation => throw exception*)
      if (v="dom") || (v="amodr") || (is_update_array_relation v) then None
      else Some (mkFalse p)
    | _ -> if has_template_b_formula (b, None) 
      then Some (mkFalse (pos_of_b_formula (b, None))) else None in
  (pr_weak,pr_strong)

let drop_lexvar_ops =
  let pr_weak b = match b with
    | LexVar t_info -> Some (mkTrue t_info.lex_loc)
    | _ -> if has_template_b_formula (b, None) 
      then Some (mkTrue (pos_of_b_formula (b, None))) else None in
  let pr_strong b = match b with
    | LexVar t_info -> Some (mkFalse t_info.lex_loc)
    | _ -> if has_template_b_formula (b, None) 
      then Some (mkFalse (pos_of_b_formula (b, None))) else None in
  (pr_weak,pr_strong)

let drop_complex_ops_z3 = drop_lexvar_ops

let memo_complex_ops stk bool_vars is_complex =
  let pr b = match b with
    | BVar(v,_) -> bool_vars # push v; None
    | _ ->
      if (is_complex b) then
        let id = fresh_old_name "memo_rel_hole_" in
        let v = SpecVar(Bool,id,Unprimed) in
        let rel_f = BForm ((b,None),None) in
        stk # push (v,rel_f);
        Some (BForm ((BVar (v,no_pos),None),None))
      else None
  in (pr, pr)

let re_order_new args inp_bool_args =
       let dec_args = List.combine args inp_bool_args in
       let pre_args, post_args = List.partition (fun (_,b) -> b) dec_args in
       let pre_args = List.map fst pre_args in
       let post_args = List.map fst post_args in
       (pre_args@post_args)

let re_order_new args inp_bool_args =
  let pr_args = pr_list !print_exp in
  Debug.no_2 "re_order_new" pr_args (pr_list string_of_bool) pr_args re_order_new args inp_bool_args

let subs_rel_formula_ops results  =
  let pr_weak b = match b with
    | RelForm (name,rel_args,p) -> 
      (try
         let (_,args,pc,post,_) =
           List.find (fun (n,args,pc,post,_)->(name_of_sv n)=(name_of_sv name)) results in
        let () = x_binfo_hp (add_str "subs_rel_formula : " !print_p_formula) b p in
        let () = x_binfo_hp (add_str "subs_rel_formula (formal para) : " (pr_list !print_exp)) args p in
        let () = x_binfo_hp (add_str "subs_rel_formula (rel_args) : " (pr_list !print_exp)) rel_args p in
        let () = x_binfo_hp (add_str "subs_rel_formula (reorder) : " (pr_option (pr_list string_of_bool))) pc p in
        let () = x_binfo_hp (add_str "subs_rel_formula (post) : " !print_formula) post p in
        let new_rel_args = match pc with
          | None -> rel_args
          | Some bl -> re_order_new rel_args bl in
        (* let subs = List.combine (List.map get_var args) (List.map get_var new_rel_args) in *)
        let subs = List.combine (List.map get_var args) new_rel_args in
        let new_f = apply_par_term subs post in
        
        let () = x_binfo_hp (add_str "subs_rel_formula (new post ) : " (!print_formula)) new_f p in
        let () = x_binfo_hp (add_str "subs_rel_formula (new_rel_args) : " (pr_list !print_exp)) new_rel_args p in
        Some (new_f)
      with _ -> None)
    | _ -> None in
  let pr_strong b = match b with
    | RelForm (_,_,p) -> 
      let () = x_tinfo_pp "WARNING:subs_rel_formula in contrvariant position" p in
      Some (mkFalse p)
    | _ -> None in
  (pr_weak,pr_strong)

(* let process_tables results = *)
(*   List.map (fun (r,post,pre) -> match r with *)
(*       | BForm ((RelForm (name,args,_),_),_) -> (name,args,post,pre) *)
(*       | _ -> report_error no_pos ("process_tables expecting relation but got:"^(!print_formula r)) *)
(*     ) results *)

(* (==fixpoint.ml#150==) *)
(* subs_rel_formula@1 *)
(* subs_rel_formula inp1 : flted_71_1374=0 & PPP(mmmm_1376,n1_1377,n,k,m) & s_1373=s' & n<=k & 0<=m *)
(* subs_rel_formula@1 EXIT: flted_71_1374=0 & true & s_1373=s' & n<=k & 0<=m *)
let subs_rel_formula results (f:formula) : formula =
  (* let new_res = process_tables results in *)
  let (pr_weak,pr_strong) = subs_rel_formula_ops results in
  drop_formula pr_weak pr_strong f

let subs_rel_formula results (f:formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "subs_rel_formula" pr pr (subs_rel_formula results) f

let check_nonlinear e =
  let flag = ref false in
  let f_None _ = None in
  let rec f_exp e = match e with
    | Mult(a1,a2,l) ->
          begin
            match a1 with
              | IConst (i, _) -> f_exp a2
              | _ -> match a2 with
                  | IConst (i, _) -> f_exp a1
                  | _ -> (flag := true; Some e)
          end
    | _ -> None
  in
  let f_Some x = Some x in
  let f = (f_None, f_None, f_None, f_None, f_exp) in
  let _ = transform_formula f e in
  !flag

let rec nonlinear_exp a = match a with
  | Mult(a1,a2,l) ->
        begin
          match a1 with
            | IConst (i, _) -> nonlinear_exp a2
            | _ -> match a2 with
                | IConst (i, _) ->  nonlinear_exp a1
                | _ -> true
        end
  | Add (a1, a2, _) 
  | Subtract (a1, a2, _) ->  nonlinear_exp a1 || nonlinear_exp a2
  | _ -> false

let check_nonlinear b =
  match b with
      Lt (a1, a2, _) 
    | Lte (a1, a2, _) 
    | Gt (a1, a2, _) 
    | Gte (a1, a2, _) 
    | Eq (a1, a2, _) 
    | Neq (a1, a2, _) 
    | EqMin (_,a1, a2, _) 
    | EqMax (_,a1, a2, _) 
        -> nonlinear_exp a1 || nonlinear_exp a2
    | _ -> false

let drop_nonlinear_formula_ops =
  let pr_weak b = 
    if check_nonlinear b then Some (mkTrue (pos_of_b_formula (b, None)))
    else None in
  let pr_strong b = 
    if check_nonlinear b then Some (mkFalse (pos_of_b_formula (b, None)))
    else None in
  (pr_weak,pr_strong)

let drop_nonlinear_formula_ops_rev =
  let (pr1,pr2) = drop_nonlinear_formula_ops in
  (pr2,pr1)

let drop_nonlinear_formula (f:formula) : formula =
  let (pr_weak,pr_strong) = drop_nonlinear_formula_ops in
  drop_formula pr_weak pr_strong f

let drop_nonlinear_formula_rev (f:formula) : formula =
  (* let cnt = new Gen.counter 0 in *)
  let (pr_weak,pr_strong) = drop_nonlinear_formula_ops in
  (* let pr_weak x = cnt # inc; pr_weak x in *)
  (* let pr_strong x = cnt # inc; pr_strong x in *)
  let pr = !print_formula in
  let nf = drop_formula pr_strong pr_weak f in
  (* let c = cnt#get in *)
  (* if (c) > 0 then *)
  (*   let () = x_tinfo_hp (add_str "non-linear detected" string_of_int) c no_pos in *)
  (*   let () = x_tinfo_hp (add_str "DROP non-linear (BFE)" pr) f no_pos in *)
  (*   let () = x_tinfo_hp (add_str "DROP non-linear (AFT)" pr) nf no_pos in *)
    nf
  (* else nf *)

let drop_nonlinear_formula (f:formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "drop_nonlinear_formula" pr pr drop_nonlinear_formula f

let drop_nonlinear_formula_rev (f:formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "drop_nonlinear_formula_rev" pr pr drop_nonlinear_formula_rev f

let drop_rel_formula (f:formula) : formula =
  let (pr_weak,pr_strong) = drop_rel_formula_ops in
  (* let (pr_weak,pr_strong) = drop_rel_formula_ops_with_filter ["BasePtr"] in *)
  drop_formula pr_weak pr_strong f
;;

let drop_rel_formula_and_return f =
  let (pr_weak,pr_strong) = drop_rel_formula_ops in
  drop_formula_and_return pr_weak pr_strong f
;;

(* Generated template name for unknown relations *)
let rel_templs_transformer = ref ([]:(spec_var*(string*string)) list)
;;


  
                

  
let trans_rel_to_templ rel =
  match rel with
  | RelForm (name,arglist,loc) ->
     (
       let (_,(t1,t2)) =
         (
           try
             List.find (fun (n,_) -> eq_spec_var name n) !rel_templs_transformer
           with Not_found ->
             let tname1 = Globals.fresh_any_name "templ" in
             let tname2 = Globals.fresh_any_name "templ" in
             let () = rel_templs_transformer := ((name,(tname1,tname2))::(!rel_templs_transformer)) in
             (name,(tname1,tname2))
         )
       in
       (match arglist with
        | b1::(b2::others) ->
           let t1 = mkTemplateExp t1 others no_pos in
           let f1 = mkEqExp b1 t1 no_pos in
           let t2 = mkTemplateExp t2 others no_pos in
           let f2 = mkEqExp b2 t2 no_pos in
           mkAnd f1 f2 no_pos
        | _ -> failwith "trans_rel_to_templ: Not valid input"
       )  
     )
  | _ -> failwith "trans_rel_to_templ: Not valid input"
;;

let trans_pure_assume_to_templ p1 =
  let (newf, rels) = drop_rel_formula_and_return p1 in
  let templ_of_rel =
    match rels with
    | h::tail ->
       trans_rel_to_templ h
    | [] -> mkTrue no_pos
  in
  remove_dupl_conj_pure (!simplify (!simplify (mkAnd templ_of_rel newf no_pos)))
;;


  
  
let strong_drop_rel_formula (f:formula) : formula =
  let (pr_weak,pr_strong) = drop_rel_formula_ops in
  drop_formula pr_strong pr_weak f

let find_all_nonlinear f = []

let build_nl_table nl = []

let replace_nonlinear f nl = f

(* extract non-linear expr and replace by fresh var *)
(* a*b>=1 |- b*a>=0   ==>   z=a*b & z>=1 |- z>=0*)
let extr_nonlinear_formula (f:formula) : formula =
  let nl_list = find_all_nonlinear f in
  let nl_table = build_nl_table nl_list in
  replace_nonlinear f nl_table

let find_eq_at_toplevel e =
  let f_f f = 
    (match f with
     | And _ | AndList _  | BForm _ -> None 
     | _ -> Some [])
  in
  let f_bf bf = 
    (match bf with
     | (Eq (e1,e2,_)) ,_ -> Some ([(e1,e2)]) 
     | _,_ -> Some ([])
    )
  in
  let f_e e = Some ([]) in
  (* let f_arg = (fun _ _ -> ()),(fun _ _ -> ()),(fun _ _ -> ()) in *)
  (* let subs e = trans_formula e () (f_f,f_bf,f_e) f_arg List.concat in *)
  let find_eq e = fold_formula e (f_f,f_bf,f_e) List.concat in
  let eq_list = find_eq e in
  eq_list

let find_eq_at_toplevel e =
  Debug.no_1 "find_eq_at_toplevel" !print_formula (pr_list (pr_pair !print_exp !print_exp)) find_eq_at_toplevel e
;;

let add_to_eqmap eq_list eqset =
  (* ZH:TODO use EMapSV to build an equality map involving variable  *)
  let eqset = List.fold_left (fun eset (e1,e2) -> 
      (* let (p_f,bf_ann) = exp in *)
      (* (match p_f with *)
      (*  | Eq (e1,e2,pos) ->  *)
         (match e1,e2 with
          | Var(sv1,_),Var(sv2,_) -> EMapSV.add_equiv eset sv1 sv2
          | Var(sv,_),IConst(i,_)  
          | IConst(i,_),Var(sv,_) -> EMapSV.add_equiv eset sv (mk_sp_const i)
          (* | IConst(i1,_),IConst(i2,_) -> EMapSV.add_equiv eset (mk_sp_const i1)(mk_sp_const i2) *)
          | _  -> eset)
       (* | _ -> eset) *)
    ) eqset eq_list in eqset 
;;


(* Assuming that there is no subtraction and multipication, because of the arith_simplify *)
(* let equality_to_matrix eq_list = *)
(*   let sv_set = *)
(*     List.fold_left ( *)
(*       fun r (e1,e2) -> *)
(*         SVarSet_eq.union r (SVarSet_eq.of_list ((var_list_exp e1)@(var_list_exp e2))) *)
(*     ) SVarSet_eq.empty eq_list *)
(*   in *)
(*   let sv_list = *)
(*     SVarSet_eq.fold (fun sv l->sv::l) sv_set [] *)
(*   in *)
(*   let matrix = *)
(*     List.map ( *)
(*       fun (e1,e2) -> *)
(*         let svLHS = var_list_exp e1 in *)
(*         let svRHS = var_list_exp e2 in *)
(*         let constLHS = List.fold_left (fun r i -> r+i) 0 (const_exp_list_exp e1) in *)
(*         let constRHS = List.fold_left (fun r i -> r+i) 0 (const_exp_list_exp e2) in *)
(*         (List.map ( *)
(*             fun sv -> *)
(*               let lhsN = List.length (List.filter (fun item -> eq_spec_var item sv) svLHS) in *)
(*               let rhsN = List.length (List.filter (fun item -> eq_spec_var item sv) svRHS) in *)
(*               lhsN-rhsN *)
(*           ) sv_list)@[constRHS-constLHS] *)
(*     ) eq_list *)
(*   in *)
(*   (matrix,sv_list) *)
(* ;; *)

let collect_variable_list e arg=
  let rec helper e arg =
    match e with
    | Add (e1,e2,_) ->
      (helper e1 arg)@(helper e2 arg)
    | Subtract (e1,e2,_) ->
      (helper e1 arg)@(helper e2 (-arg))
    | Mult (e1,e2,_) ->
      (
        match e1,e2 with
        | IConst (i,_),othere
        | othere,IConst (i,_) ->
          helper othere (i*arg)
        | _,_ -> (helper e1 arg)@(helper e2 arg)
      )
    | Div (e1,e2,_) ->
      (
        match e1,e2 with
        | IConst (i,_),othere
        | othere,IConst (i,_) ->
          helper othere (arg/i)
        | _,_ -> (helper e1 arg)@(helper e2 arg)
      )
    | Var (sv,_) ->
      [(sv,arg)]
    | _ -> []
  in
  helper e arg
;;

let fold_variable_list vclist =
  let fold_one (sv,const) vclist =
    List.filter (fun (nsv,nconst) -> if eq_spec_var sv nsv then true else false) vclist
  in
  List.map (
    fun ((sv,const) as vc) ->
      let lst = List.filter (fun (nsv,nconst) -> if eq_spec_var sv nsv then true else false) vclist in
      List.fold_left (fun (sv,const) (nsv,nconst) -> (sv,nconst+const)) (List.hd lst) (List.tl lst)
  ) vclist
;;

let rec eval_constant_exp e =
  match e with
  | Add (e1,e2,_) ->
    (eval_constant_exp e1)+(eval_constant_exp e2)
  | Subtract (e1,e2,_) ->
    (eval_constant_exp e1)-(eval_constant_exp e2)
  | Mult (e1,e2,_) ->
    (eval_constant_exp e1)*(eval_constant_exp e2)
  | Div (e1,e2,_) ->
    (eval_constant_exp e1)*(eval_constant_exp e2)
  | IConst (i,_) ->
      i
  | _ -> failwith "eval_constant_exp: Invalid input"
;;

let rec constantize_exp e=
  match e with
  | Add (e1,e2,l) ->
    Add (constantize_exp e1,constantize_exp e2,l)
  | Subtract (e1,e2,l) ->
    Subtract (constantize_exp e1,constantize_exp e2,l)
  | Mult (e1,e2,l) ->
    Mult (constantize_exp e1,constantize_exp e2,l)
  | Div (e1,e2,l) ->
    Div (constantize_exp e1,constantize_exp e2,l)
  | IConst _ -> e
  | _ -> IConst (0,no_pos)
;;

let equality_to_matrix eq_list =
  let sv_set =
    List.fold_left (
      fun r (e1,e2) ->
        SVarSet_eq.union r (SVarSet_eq.of_list ((var_list_exp e1)@(var_list_exp e2)))
    ) SVarSet_eq.empty eq_list
  in
  let sv_list =
    SVarSet_eq.fold (fun sv l->sv::l) sv_set []
  in
  let matrix =
    List.map (
      fun (e1,e2) ->
        let var_info = fold_variable_list ((collect_variable_list e1 1)@(collect_variable_list e2 (-1))) in
        let () = x_tinfo_pp ("var_info "^((pr_list (pr_pair !print_sv string_of_int)) var_info)) no_pos in
        let () = x_tinfo_pp ("sv_list "^((pr_list !print_sv) sv_list)) no_pos in
        let constLHS = eval_constant_exp (constantize_exp e1) in
        let constRHS = eval_constant_exp (constantize_exp e2) in
        (List.map (
            fun sv ->
              let (old_sv,v) =
                try
                  List.find (fun (nsv,nv) -> if eq_spec_var nsv sv then true else false) var_info
                with _ ->
                  (sv,0)
              in
              v
          ) sv_list)@[constRHS-constLHS]
    ) eq_list
  in
  (matrix,sv_list)
;;



let equality_to_matrix eq_list =
  Debug.no_1 "equality_to_matrix" (pr_list (pr_pair !print_exp !print_exp)) (pr_pair (pr_list (pr_list string_of_int)) !print_svl)  equality_to_matrix eq_list
;;

let enhance_eq_list eq_list =
    let (matrix,svlst) = equality_to_matrix eq_list in
    let res_list = Matrix.solve_equation matrix in
    let () = x_tinfo_pp ("res_list"^((pr_list (pr_pair string_of_int string_of_int)) res_list)) no_pos in
    let new_eq = (List.map (fun (pos,v) -> (Var (List.nth svlst pos,no_pos),IConst (v,no_pos))) res_list) in
    let new_pure = join_conjunctions (List.map (fun (l,r) -> mkEqExp l r no_pos) new_eq) in
    let orig_pure = join_conjunctions (List.map (fun (l,r) -> mkEqExp l r no_pos) eq_list) in
    let () = if !Globals.assert_nonlinear then 
        let b = !tp_imply orig_pure new_pure in
        if not(b) then 
          let () = x_dinfo_hp (add_str "XXX:orig_eqn" !print_formula) orig_pure no_pos in
          let () = x_dinfo_hp (add_str "XXX:new_eqn" !print_formula) new_pure no_pos in
          let () = x_dinfo_pp "XXX:UNSOUND enhance_eq_list" no_pos in
          failwith "UNSOUND enhance_eq_list"
        else  () (* failwith "SOUND enhance_eq_list" *)
            (* () *) (* x_tinfo_pp "XXX:OK enhance_eq_list" no_pos *)  
      else ()
    in
    new_eq@eq_list
;;

let enhance_eq_list eq_list =
  if true (* !Globals.non_linear_flag *) then
    Debug.no_1 "enhance_eq_list" (pr_list (pr_pair !print_exp !print_exp)) (pr_list (pr_pair !print_exp !print_exp)) enhance_eq_list eq_list
  else
    eq_list
;;


let build_eqmap eq_list =
  let eqset = EMapSV.mkEmpty in
  add_to_eqmap eq_list eqset

  (*  new processing of equality with constant propagation ..

      x=a*b & b=1+2 & a=1 |- RHS
      ===>  ([a=1], [(x,a*b);(b,1+2)])
      ===>  ([a=1,b=3], [(x,a*1)])
      ===>  ([a=1,b=3], [(x,3*1)])
      ===>  ([a=1,b=3,x=3], 

      x=d*b & b=1+a & a=1 |- RHS
      ===>  ([a=1], [(x,d*b);(b,1+a)])
      ===>  ([a=1], [(x,d*b);(b,1+1)])
      ===>  ([a=1,b=1], [(x,d*1)])
      ===>  ([a=1,b=1], [(x,d)])
      ===>  ([a=1,b=1,x=d], [])

      ===>  ([b=1,a=3], [(x,a*1)])
      ===>  ([b=1,a=3], [(x,3*1)])
      ===>  ([b=1,a=3,x=3], 

  *)
let find_const_sv sv =
  match sv with
  | SpecVar (_,str,_) ->
    get_int_const str
;;

let spec_with_const em sv l =
  let eqlst = EMapSV.find_equiv_all_new sv em in
  let eqconst =
    List.fold_left
      (fun r item ->
         match find_const_sv item with
         | Some i -> Some i
         | None -> r
      ) None eqlst
  in
  match eqconst with
  | Some i -> (IConst (i,no_pos))
  | None -> Var (sv,l)
;;

(* let add_to_em_set eq_list em_set = *)
(*   let matrix = equality_to_matrix eq_list in *)
(*   let () = x_tinfo_pp ("matrix: "^(Matrix.print_matrix string_of_int matrix)) no_pos in *)
(*   let (em,eset) = List.fold_left (fun (em,set) (e1,e2) -> *)
(*          (match e1,e2 with *)
(*           | Var(sv1,_),Var(sv2,_) -> (EMapSV.add_equiv em sv1 sv2, set) *)
(*           | Var(sv,_),IConst(i,_)  | IConst(i,_),Var(sv,_) -> (EMapSV.add_equiv em sv (mk_sp_const i), set) *)
(*           | Var(sv,_),e  | e,Var(sv,_) -> (em, (sv,e)::set) *)
(*           | _  -> em_set) *)
(*     ) em_set eq_list *)
(*   in *)
(*   let eval_set (em,eset) = *)
(*     let rec eval_one em e = *)
(*       match e with *)
(*       | Add (e1,e2,_) -> *)
(*         ( *)
(*           match eval_one em e1, eval_one em e2 with *)
(*           | Some i1, Some i2 -> *)
(*             Some (i1+i2) *)
(*           | _,_ -> *)
(*             None *)
(*         ) *)
(*       | Mult (e1,e2,_) -> *)
(*         ( *)
(*           match eval_one em e1, eval_one em e2 with *)
(*           | Some i1, Some i2 -> *)
(*             Some (i1*i2) *)
(*           | _,_ -> *)
(*             None *)
(*         ) *)
(*       |  Subtract (e1,e2,_) -> *)
(*         ( *)
(*           match eval_one em e1, eval_one em e2 with *)
(*           | Some i1, Some i2 -> *)
(*             Some (i1-i2) *)
(*           | _,_ -> *)
(*             None *)
(*         ) *)
(*       | Var (sv,l) -> *)
(*         ( *)
(*           match spec_with_const em sv l with *)
(*           | IConst (i,_) -> Some i *)
(*           | _ -> None *)
(*         ) *)
(*       | IConst (i,_) -> *)
(*         Some i *)
(*       | _ -> *)
(*         None *)
(*     in *)
(*     let process (em,signal,neset) (sv,e) = *)
(*       match eval_one em e with *)
(*       | None -> (em,signal||false,(sv,e)::neset) *)
(*       | Some iconst -> *)
(*         (EMapSV.add_equiv em sv (mk_sp_const iconst), true, neset) *)
(*     in *)
(*     List.fold_left process (em,false,[]) eset *)
(*   in *)
(*   let rec iterator em eset = *)
(*     let (rem,rsignal,neset) = eval_set (em,eset) in *)
(*     if rsignal then iterator rem neset *)
(*     else rem *)
(*   in *)
(*   iterator em eset *)
(* ;; *)

let add_to_em_set eq_list em_set =
  let (em,eset) =
    List.fold_left (fun (em,set) (e1,e2) ->
        (
          match e1,e2 with
          | Var(sv1,_),Var(sv2,_) ->
            (EMapSV.add_equiv em sv1 sv2, set)
          | Var(sv,_),IConst(i,_)
          | IConst(i,_),Var(sv,_) ->
            (EMapSV.add_equiv em sv (mk_sp_const i), set)
          | Var(sv,_),e
          | e,Var(sv,_) ->
            (em, (sv,e)::set)
          | _  -> (em,set)
        )
      ) em_set eq_list
  in
  let () = x_tinfo_pp ("em "^(EMapSV.string_of em)) no_pos in
  em
;;

(* building an eq_map for pure of top-level *)
let build_eqmap_at_toplevel e =
  let eq_list = find_eq_at_toplevel e in
   build_eqmap eq_list

let add_eqmap_at_toplevel em e =
  let eq_list = find_eq_at_toplevel e in
  (* let matrix = equality_to_matrix eq_list in *)
  (* let () = x_tinfo_pp ("matrix: "^(Matrix.print_matrix string_of_int matrix)) no_pos in *)
  (* let new_matrix = Matrix.gaussian_elimination_int matrix in *)
  (* let () = x_tinfo_pp ("new_matrix: "^(Matrix.print_matrix string_of_float new_matrix)) no_pos in *)
  (* let res_list = Matrix.solve_equations matrix in *)
  (* let extra_eq_list = List.fold_left  *)
  let new_eq_list = x_add_1 enhance_eq_list eq_list in
  let new_em = add_to_em_set new_eq_list (em,[]) in
  
  (*add_to_eqmap eq_list em*)
  new_em

(* let find_eq_all e = build_eqmap_at_toplevel e *)
(*   let f_f f =  *)
(*     (match f with *)
(*      | And _ | AndList _  | BForm _ -> None  *)
(*      | _ -> Some []) *)
(*   in *)
(*   let f_bf bf =  *)
(*     (match bf with *)
(*      | (Eq _) ,_ -> Some ([bf])  *)
(*      | _,_ -> Some ([]) *)
(*     ) *)
(*   in *)
(*   let f_e e = Some ([]) in *)
(*   (\* let f_arg = (fun _ _ -> ()),(fun _ _ -> ()),(fun _ _ -> ()) in *\) *)
(*   (\* let subs e = trans_formula e () (f_f,f_bf,f_e) f_arg List.concat in *\) *)
(*   let find_eq e = fold_formula e (f_f,f_bf,f_e) List.concat in *)
(*   let eq_list = find_eq e in *)
(*   (\* ZH:TODO use EMapSV to build an equality map involving variable  *\) *)
(*   let eqset = EMapSV.mkEmpty in *)
(*   let eqset = List.fold_left (fun eset exp ->  *)
(*       let (p_f,bf_ann) = exp in *)
(*       (match p_f with *)
(*        | Eq (e1,e2,pos) ->  *)
(*          (match e1,e2 with *)
(*           | Var(sv1,_),Var(sv2,_) -> EMapSV.add_equiv eset sv1 sv2 *)
(*           | Var(sv1,_),IConst(i2,_) -> EMapSV.add_equiv eset sv1 (mk_sp_const i2) *)
(*           | IConst(i1,_),Var(sv2,_) -> EMapSV.add_equiv eset (mk_sp_const i1) sv2 *)
(*           | IConst(i1,_),IConst(i2,_) -> EMapSV.add_equiv eset (mk_sp_const i1)(mk_sp_const i2) *)
(*           | _  -> eset) *)
(*        | _ -> eset) *)
(*     ) eqset eq_list in eqset  *)
(* ;; *)



(* WN : Not working under negation *)
(* (==omega.ml#631==) *)
(* subs_const_var_formula@3 *)
(* subs_const_var_formula inp1 : (not((a=1 & 1<=(a*b))) | 1<=b) *)
(* subs_const_var_formula@3 EXIT: (not((a=1 & 1<=(a*b))) | 1<=b) *)
(* a=c & c=1 & a*b>=1 |- b>=0   ==>   1*b>=1 & a=1 |- b>=0*)
(* v1=v2 & v1=c & lhs |- (ex r=c & rhs) *)
(* let subs_const_var_formula (f:formula) : formula = *)
(*   let f_f a e = None in *)
(*   let f_bf a (pf,ann) = *)
(*     match pf with *)
(*     | Eq (e1,e2,pos) -> *)
(*       ( *)
(*         match e1,e2 with *)
(*         | Var (sv1,_), IConst (i1,_) *)
(*         | IConst (i1,_), Var (sv1,_) -> *)
(*           Some (pf,ann) *)
(*         | _ -> None *)
(*       ) *)
(*     | _ -> None *)
(*   in *)
(*   let f_e a e = *)
(*     match e with *)
(*     | Var (sv,_) -> *)
(*       let eqlst = EMapSV.find_equiv_all_new sv a in *)
(*       let eqconst = *)
(*         List.fold_left *)
(*           (fun r item -> *)
(*              match find_const_sv item with *)
(*              | Some i -> Some i *)
(*              | None -> r *)
(*           ) None eqlst *)
(*       in *)
(*       ( *)
(*         match eqconst with *)
(*         | Some i -> Some (IConst (i,no_pos)) *)
(*         | None -> Some e *)
(*       ) *)
(*     | _ -> None *)
(*   in *)
(*   let ff = (f_f,f_bf,f_e) in *)
(*   let f_arg_1 a e = a in *)
(*   let f_arg = (f_arg_1,f_arg_1,f_arg_1) in *)
(*   let eq_map = build_eqmap_at_toplevel (\* find_eq_all *\) f in *)
(*   let () = x_tinfo_pp (EMapSV.string_of eq_map) no_pos in *)
(*   map_formula_arg f eq_map ff f_arg *)



(*
new substitute to work under negation & quantifiers
but not implication

(==omega.ml#517==)
subs_const_var_formula@1
subs_const_var_formula inp1 : forall(b:1<=(a*b)) & a=1
subs_const_var_formula@1 EXIT: forall(b:1<=(1*b)) & a=1

(==omega.ml#517==)
subs_const_var_formula@2
subs_const_var_formula inp1 : forall(a:1<=(a*b)) & a=1
subs_const_var_formula@2 EXIT: forall(a:1<=(a*b)) & a=1

(==omega.ml#517==)
subs_const_var_formula@1
subs_const_var_formula inp1 : 1<=(a*b) & a=1
subs_const_var_formula@1 EXIT: 1<=(1*b) & a=1

!!! **cpure.ml#11034:emap[]
(==omega.ml#632==)
subs_const_var_formula@2
subs_const_var_formula inp1 : (not((a=1 & 1<=(a*b))) | 1<=b)
subs_const_var_formula@2 EXIT: (not((a=1 & 1<=(1*b))) | 1<=b)

Can we use eqmap of LHS for conseq but
how far can we go?

Fails for implication
=====================
!!! **cpure.ml#11034:emap[]
(==omega.ml#632==)
subs_const_var_formula@2
subs_const_var_formula inp1 : (not((a=1 & 1<=b)) | 1<=(a*b))
subs_const_var_formula@2 EXIT: (not((a=1 & 1<=b)) | 1<=(a*b))

  not(x=3 & LHS) \/ RHS
  <==>  not(x=3 & LHS) \/ RHS[x->3]
*)
let rec subs_const_var_formula ?(em=None) (f:formula) : formula =
  let is_neg f = match f with
    | Not _ -> true
    | _ -> false in
  let extr_neg f = match f with
    | Not (l,_,_) -> l
    | _ -> failwith "subs_const: expects neg here" in
  let f_f ((sflag,em,nonlinear) as em_arg) e = 
    if sflag then
      let lst = split_disjunctions e in
      if List.length lst <= 1 then None
      else let (neglst,dislst) = List.partition (is_neg) lst in
        match neglst with
        | [] -> None
        | lhs::rest -> 
          let () = x_dinfo_hp (add_str "subs_const (neg)" !print_formula) lhs no_pos in
          (* need a special case for not(LHS) \/ RHS *)
          (* build_eqmap for LHS *)
          (* use it as starting for RHS *)
          let rhs = rest@dislst in
          let f = extr_neg lhs in
          let eqlist = find_eq_at_toplevel f in
          let emap = em in
          (* let _ = add_eqmap_at_toplevel emap f in *)
          (* let new_em = (true,add_to_eqmap eqlist emap) in *)
          let new_em = (true,add_eqmap_at_toplevel emap f,nonlinear) in
          let new_rhs = List.map (subs_const_var_formula ~em:(Some new_em)) rhs in
          let new_lhs = subs_const_var_formula ~em:(Some em_arg) lhs in
          Some (join_disjunctions (new_lhs::new_rhs))
    else None
  in
  let f_bf a ((pf,ann) as f) =
    match pf with
    | Eq (e1,e2,pos) ->
      begin
        match e1,e2 with
        | Var _, IConst _ | IConst _, Var _ | Var _, Var _
          (* no change to the vars here *)
          -> Some f
        | _ -> None
      end
    | _ -> None
  in
  let f_e (_,em,nonlinear) e =
    match e with
    | Var (sv,l) ->
      if nonlinear then
        Some(spec_with_const em sv l)
      else Some e
    | _ -> None
  in
  let f_arg_f (start_flag,emap,nonlinear) e =
    match e with
    | And _
    | AndList _ ->
      if start_flag then (* add to eqmap *)
        let eqlist = find_eq_at_toplevel e in
        (false,add_eqmap_at_toplevel emap e,nonlinear)
      else (* inside ; no change to eqmap *)
        (false,emap,nonlinear)
    | Or _ | Not _ ->  (* re-start *)
      (true,emap,nonlinear)
    | Forall (v,_,_,_) | Exists (v,_,_,_) ->
      (* change vs_set vs-v *)
      (true,EMapSV.elim_elems_one emap v,nonlinear)
    | BForm _ -> (false,emap,nonlinear)
  in
  let f_arg_bf (s,em,nonlinear) e =
    (s,em,false)
  in
  let f_arg_e (s,em,nonlinear) e =
    match e with
    | Mult _ -> (s,em,true)
    | _ -> (s,em,nonlinear)
  in
  let ff = (f_f,f_bf,f_e) in
  let f_arg_1 a e = a in
  let f_arg = (f_arg_f,f_arg_bf,f_arg_e) in
  let init_arg = match em with
    | None -> (true,EMapSV.mkEmpty,false) (* build_eqmap_at_toplevel (\* find_eq_all *\) f *) 
    | Some em -> em (* add_emap_at_toplevel em f *)
  in
  (* let () = x_tinfo_pp ((add_str "subs_const(emap)" EMapSV.string_of) eq_map) no_pos in *)
  if !Globals.non_linear_flag then map_formula_arg f init_arg ff f_arg
  else f

let subs_const_var_formula (f:formula) : formula =
  let pr = !print_formula in
   Debug.no_1 "subs_const_var_formula" pr pr subs_const_var_formula f

let drop_rel_formula (f:formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "drop_rel_formula" pr pr drop_rel_formula f

let drop_sel_rel_formula (f:formula) sel_svs : formula =
  let ps = list_of_conjs f in
  let ps1 = List.fold_left (fun r p ->
      match p with
      | BForm (bf,_) ->
        (match bf with
         | (RelForm(rel,_,_),_) ->
           if mem_svl rel sel_svs then r else r@[p]
         | _ -> r@[p])
      | _ -> r@[p]
    ) [] ps in
  conj_of_list ps1 (pos_of_formula f)

let memoise_formula_ho is_complex (f:formula) : 
  (formula * ((spec_var * formula) list) * (spec_var list)) =
  let stk = new Gen.stack in
  let bool_vars = new Gen.stack in
  let (pr_w,pr_s) = memo_complex_ops stk bool_vars is_complex in
  (* let pr b = match b with *)
  (*   | BVar(v,_) -> bool_vars # push v; None *)
  (*   | _ -> *)
  (*         if (is_complex b) then *)
  (*           let id = fresh_old_name "memo_rel_hole_" in *)
  (*           let v = SpecVar(Bool,id,Unprimed) in *)
  (*           let rel_f = BForm ((b,None),None) in *)
  (*           stk # push (v,rel_f); *)
  (*           Some (BForm ((BVar (v,no_pos),None),None)) *)
  (*         else None  *)
  (* in  *)
  let f = drop_formula pr_w pr_s f in
  let ans = stk # get_stk in
  (f,ans, bool_vars # get_stk)

let memoise_formula_ho isC (f:formula) : 
  (formula * ((spec_var * formula) list) * (spec_var list)) =
  let pr = !print_formula in
  let pr2 = pr_triple pr (pr_list (pr_pair !print_sv pr)) (!print_svl) in
  Debug.no_1 "memoise_formula_ho" pr pr2 (fun _ -> memoise_formula_ho isC f) f

let memoise_rel_formula ivs (f:formula) : 
  (formula * ((spec_var * formula) list) * (spec_var list)) =
  let pr b = match b with
    | RelForm (i,_,p) -> mem i ivs
    | _ ->
      (* Template: For soundness, do not remove 
       * templates which contains bound variables *)
      let bf = (b, None) in
      if has_template_b_formula bf then 
        Gen.BList.subset_eq eq_spec_var 
          (List.filter (fun v -> not (is_FuncT (type_of_spec_var v))) (bfv bf)) 
          (fv f)
      else false
  in memoise_formula_ho pr f

let memoise_rel_formula ivs (f:formula) : 
  (formula * ((spec_var * formula) list) * (spec_var list)) =
  let pr = !print_formula in
  let pr2 = pr_triple pr (pr_list (pr_pair !print_sv pr)) (!print_svl) in
  Debug.no_2 "memoise_rel_formula" !print_svl pr pr2 (fun _ _ -> memoise_rel_formula ivs f) ivs f

let memoise_all_rel_formula (f:formula) : 
  (formula * ((spec_var * formula) list) * (spec_var list)) =
  let pr b = match b with
    | RelForm (i,_,p) -> true
    | _ -> if has_template_b_formula (b, None) then true else false
  in memoise_formula_ho pr f

let mk_bvar_subs v subs =
  try
    let (_,memo_f) = List.find (fun (i,_) -> eq_spec_var v i) subs in
    memo_f
  with _ -> 
    (match v with
     | SpecVar(_,id,p) -> (mkBVar_pure id p no_pos))

let mk_neg_bvar_subs v subs =
  let e = mk_bvar_subs v subs in
  mkNot e None no_pos

(*
  v>0, 0<v, v>=1, 1<=v --> v
  v<=0, 0>=v, v<1, 1>v --> !v
  v1=v2
  v1!=v2

*)
let restore_bool_omega bf bvars subs =
  match bf with
  | BVar (v,_)
  | Lt (IConst(0,_),Var(v,_),_) 
  | Lte (IConst(1,_),Var(v,_),_) 
  | Gt(Var(v,_),IConst(0,_),_) 
  | Gte(Var(v,_),IConst(1,_),_) 
    -> if mem v bvars then Some(mk_bvar_subs v subs) else None
  | Gte (IConst(0,_),Var(v,_),_) 
  | Lte(Var(v,_),IConst(0,_),_) 
  | Gt (IConst(1,_),Var(v,_),_) 
  | Lt(Var(v,_),IConst(1,_),_) 
    -> if mem v bvars then Some(mk_neg_bvar_subs v subs) else None
  | _ -> None

let restore_memo_formula subs bvars (f:formula) : formula =
  let bvars = bvars@(List.map fst subs) in
  let pr b = restore_bool_omega b bvars subs in
  drop_formula pr pr f
(* let ps = split_conjunctions f in *)
(* let ps1 = List.map (drop_formula pr pr) ps in *)
(* conj_of_list ps1 (pos_of_formula f) *)

let restore_memo_formula subs bvars (f:formula) : formula =
  let pr = !print_formula in
  let pr2 = (pr_list (pr_pair !print_sv pr)) in
  Debug.no_3 "restore_rel_formula" pr2 !print_svl pr pr (fun _ _ _ -> restore_memo_formula subs bvars f) subs bvars f

let comb_disj nxs : formula =
  let rec helper nxs f =
    match nxs with
    | [] -> f
    | []::_ -> mkTrue no_pos
    | nx::nxs -> 
      let nx = join_conjunctions nx in
      helper nxs (mkOr nx f None no_pos)
  in helper nxs (mkFalse no_pos)

let remove_conj x xs =
  let rec helper xs ac =
    match xs with
    | [] -> None
    | b::bs -> if equalFormula_f eq_spec_var b x then Some (ac@bs)
      else helper bs (b::ac) 
  in helper xs []

let remove_common x nxs =
  let rs = List.map (remove_conj x) nxs in
  if List.exists (fun x -> x==None) rs then
    None
  else Some (List.map (fun m -> match m with 
      | None -> []
      | Some xs -> xs) rs)

let simplify_disj_aux nx nxs : formula =
  let rec helper nx nxs rx cx =
    match nx with 
    | [] -> 
      let r = comb_disj (rx::nxs) in
      let c = join_conjunctions cx in
      mkAnd r c no_pos
    | (x::nx) -> 
      begin
        match (remove_common x nxs) with
        | None -> helper nx nxs (x::rx) cx
        | Some nxs -> helper nx nxs rx (x::cx)
      end
  in helper nx nxs [] []


(* assumes absence of duplicates *)
let simplify_disj_new (f:formula) : formula =
  let fs=split_disjunctions f in
  match fs with
  | [] -> report_error no_pos ("simplify_disj : not possible to have empty disj")
  | [x] -> x
  | x::xs -> 
    let nx = split_conjunctions x in
    let nxs = List.map split_conjunctions xs in
    simplify_disj_aux nx nxs

let simplify_disj_new (f:formula) : formula =
  let pr = !print_formula in
  Debug.no_1 "simplify_disj_new" pr pr simplify_disj_new f

(* let fv_wo_rel (f:formula) = *)
(*   let vs = fv f in *)
(*   List.filter (fun v -> not(is_RelT (type_of_spec_var v))) vs *)

(* Termination: Add the call numbers and the implicit phase 
 * variables to specifications if the option 
 * --dis-call-num and --dis-phase-num are not enabled (default) *) 
let rec add_term_nums_pure f log_vars call_num phase_var =
  match f with
  | BForm (bf, lbl) ->
    let n_bf, pv = add_term_nums_b_formula bf log_vars call_num phase_var in
    (BForm (n_bf, lbl), pv)
  | And (f1, f2, pos) ->
    let n_f1, pv1 = add_term_nums_pure f1 log_vars call_num phase_var in
    let n_f2, pv2 = add_term_nums_pure f2 log_vars call_num phase_var in
    (And (n_f1, n_f2, pos), pv1 @ pv2)
  | AndList b -> let l1,l2 = map_l_snd_res (fun c-> add_term_nums_pure c log_vars call_num phase_var) b in
    (AndList l1, List.concat l2)
  | Or (f1, f2, lbl, pos) ->
    let n_f1, pv1 = add_term_nums_pure f1 log_vars call_num phase_var in
    let n_f2, pv2 = add_term_nums_pure f2 log_vars call_num phase_var in
    (Or (n_f1, n_f2, lbl, pos), pv1 @ pv2)
  | Not (f, lbl, pos) ->
    let n_f, pv = add_term_nums_pure f log_vars call_num phase_var in
    (Not (n_f, lbl, pos), pv)
  | Forall (sv, f, lbl, pos) ->
    let n_f, pv = add_term_nums_pure f log_vars call_num phase_var in
    (Forall (sv, n_f, lbl, pos), pv)
  | Exists (sv, f, lbl, pos) ->
    let n_f, pv = add_term_nums_pure f log_vars call_num phase_var in
    (Exists (sv, n_f, lbl, pos), pv)

(* Only add call number to Term *) 
(* Add phase variable into Term only if 
 * there is not any logical var inside it *)
and add_term_nums_b_formula bf log_vars call_num phase_var =
  let (pf, ann) = bf in
  let n_pf, pv = match pf with
    | LexVar t_info ->
      let t_ann = t_info.lex_ann in
      let ml = t_info.lex_exp in
      (* let il = t_info.lex_tmp in *)
      let pos = t_info.lex_loc in
      begin match t_ann with
        | Term ->
          let v_ml, v_il, pv =
            (* Termination: If there are logical variables or 
             * consts in the first place of the measures,
             * it is no need to add phase variables *)
            let has_phase_num = 
              try is_int (List.hd ml)
              with _ -> false
            in 
            if has_phase_num then (ml, ml, [])
            else
              let mfv = List.fold_left (fun acc m -> acc @ (afv m)) [] ml in
              let log_var = Gen.BList.intersect_eq eq_spec_var mfv log_vars in
              let has_log_var = not (Gen.is_empty log_var) in
              if has_log_var then 
                (* if (List.length ml) == 1 then ([mkIConst 0 pos], []) *)
                (* else  *)
                (ml, ml, log_var)  (* existing phase logical vars here *)
              else match phase_var with
                | None -> (ml, ml, []) (* no phase numbering here *)
                | Some pv -> let nv = mkVar pv pos
                  in ([nv], nv::ml, [pv])
          in 
          let n_ml, n_il = match call_num with
            | None -> (v_ml, v_il)
            | Some i -> let c = (mkIConst i pos) in
              (c::v_ml, c::v_il)
          in (LexVar { t_info with lex_exp = n_ml; lex_tmp = n_il; }, pv)
        | TermU uid
        | TermR uid -> begin
            match call_num with
            | None -> (pf, [])
            | Some i ->
              let uid = { uid with tu_call_num = i; } in 
              (LexVar { t_info with
                        lex_ann = (match t_ann with TermU _ -> TermU uid | _ -> TermR uid);
                        lex_exp = (mkIConst i pos)::t_info.lex_exp; }, [])
          end
        | _ -> (pf, []) end
    | _ -> (pf, [])
  in ((n_pf, ann), pv)

let  add_term_nums_pure bf log_vars call_num phase_var =
  Debug.no_2 "add_term_nums_pure" (pr_option string_of_int) (pr_option !print_sv) (pr_pair !print_formula !print_svl)
    (fun _ _ -> add_term_nums_pure bf log_vars call_num phase_var) call_num phase_var

let rec count_term_pure f = 
  match f with
  | BForm (bf, _) ->
    count_term_b_formula bf
  | And (f1, f2, _) ->
    let n_f1 = count_term_pure f1 in
    let n_f2 = count_term_pure f2 in
    n_f1 + n_f2
  | AndList b -> List.fold_left (fun a (_,c) -> a+(count_term_pure c)) 0 b 
  | Or (f1, f2, _, _) ->
    let n_f1 = count_term_pure f1 in
    let n_f2 = count_term_pure f2 in
    n_f1 + n_f2
  | Not (f, _, _) -> count_term_pure f
  | Forall (_, f, _, _) -> count_term_pure f
  | Exists (_, f, _, _) -> count_term_pure f

and count_term_b_formula bf =
  let (pf, _) = bf in
  match pf with
  | LexVar t_info ->
    (match t_info.lex_ann with
     | Term -> 1
     | TermU _ -> 1 (* For TNT Inference *)
     | _ -> 0)
  | _ -> 0

let rec remove_cnts remove_vars f = match f with
  | BForm _ -> if intersect (fv f) remove_vars != [] then mkTrue no_pos else f
  | And (f1,f2,p) ->
    let res1 = remove_cnts remove_vars f1 in
    let res2 = remove_cnts remove_vars f2 in
    if isConstFalse res1 then res2
    else if isConstFalse res2 then res1
    else mkAnd res1 res2 p
  | Or (f1,f2,o,p) -> 
    let res1 = remove_cnts remove_vars f1 in
    let res2 = remove_cnts remove_vars f2 in
    if isConstTrue res1 then res2
    else if isConstTrue res2 then res1
    else mkOr res1 res2 o p
  | Not (f,o,p) -> mkNot (remove_cnts remove_vars f) o p
  | Forall (v,f,o,p) -> mkForall [v] (remove_cnts remove_vars f) o p
  | Exists (v,f,o,p) -> mkExists [v] (remove_cnts remove_vars f) o p
  | AndList _ -> report_error no_pos "unexpected AndList"

let rec remove_cnts2 keep_vars f = match f with
  | BForm _ -> if intersect (fv f) keep_vars = [] then mkTrue no_pos else f
  | And (f1,f2,p) -> 
    let res1 = remove_cnts2 keep_vars f1 in
    let res2 = remove_cnts2 keep_vars f2 in
    if isConstFalse res1 then res2
    else if isConstFalse res2 then res1
    else mkAnd res1 res2 p
  | Or (f1,f2,o,p) -> 
    let res1 = remove_cnts2 keep_vars f1 in
    let res2 = remove_cnts2 keep_vars f2 in
    if isConstTrue res1 then res2
    else if isConstTrue res2 then res1
    else mkOr res1 res2 o p
  | Not (f,o,p) -> mkNot (remove_cnts2 keep_vars f) o p
  | Forall (v,f,o,p) -> mkForall [v] (remove_cnts2 keep_vars f) o p
  | Exists (v,f,o,p) -> mkExists [v] (remove_cnts2 keep_vars f) o p
  | AndList _ -> report_error no_pos "unexpected AndList"

let rec is_num_dom_exp_0 e = match e with
  | IConst _ -> true
  | Add (e1,e2,_) -> is_num_dom_exp_0 e1 || is_num_dom_exp_0 e2
  (*  | Subtract (e1,e2,_) -> is_num_dom_exp e1 || is_num_dom_exp e2*)
  | _ -> false

let rec is_num_dom_exp e = match e with
  | IConst (0,_) -> false
  | IConst _ -> true
  | Add (e1,e2,_) -> is_num_dom_exp e1 || is_num_dom_exp e2
  | _ -> false

let get_num_dom_pf pf = match pf with
  | Lt (e1,e2,_)
  | Lte (e1,e2,_)
  | Gt (e1,e2,_)
  | Gte (e1,e2,_)
  | Neq (e1,e2,_) -> 
    if is_num_dom_exp_0 e1 || is_num_dom_exp_0 e2 then 
      let r = afv e1 @ afv e2 in
      (r,[],r) 
    else ([],[],[])
  | Eq (e1,e2,_) -> 
    begin
      match e1,e2 with
      | Var _, BagUnion _ -> ([], List.filter is_int_typ (afv e1 @ afv e2), [])
      | _ -> 
        if is_num_dom_exp e1 || is_num_dom_exp e2 then 
          let r = afv e1 @ afv e2 in
          (r,[],r) 
        else 
        if is_num_dom_exp_0 e1 || is_num_dom_exp_0 e2 then (afv e1 @ afv e2,[],[]) 
        else ([],[],[])
    end
  | _ -> ([],[],[])

let rec get_num_dom f = match f with
  | BForm ((pf,_),_) -> get_num_dom_pf pf
  | And (f1,f2,_) -> 
    let (r11,r12,r13) = get_num_dom f1 in
    let (r21,r22,r23) = get_num_dom f2 in
    (r11@r21,r12@r22,r13@r23)
  | Or (f1,f2,_,_) ->
    let (r11,r12,r13) = get_num_dom f1 in
    let (r21,r22,r23) = get_num_dom f2 in
    (r11@r21,r12@r22,r13@r23)
  | Not (f,_,_) -> get_num_dom f
  | Forall (_,f,_,_) -> get_num_dom f
  | Exists (_,f,_,_) -> get_num_dom f
  | AndList _ -> report_error no_pos "unexpected AndList"

let order_var v1 v2 vs =
  if List.exists (eq_spec_var_nop v1) vs then
    if List.exists (eq_spec_var_nop v2) vs then None
    else Some (v2,v1)
  else if List.exists (eq_spec_var_nop v2) vs then Some (v1,v2)
  else None 

let rec extr_subs xs vs subs rest = match xs with 
  | [] -> (vs,subs,rest)
  | ((v1,v2) as p)::xs1 -> let m = order_var v1 v2 vs in
    (match m with
     | None -> extr_subs xs1 vs subs (p::rest)  
     | Some ((fr,t) as p2) -> extr_subs xs1 (fr::vs) (p2::subs) rest) 

let extr_subs xs vs subs rest = 
  let pr_vars = !print_svl in
  let pr_subs = pr_list (pr_pair !print_sv !print_sv) in
  let pr_res = pr_triple pr_vars pr_subs pr_subs in
  Debug.no_2 "extr_subs" pr_subs pr_vars pr_res (fun _ _ -> extr_subs xs vs subs rest) xs vs 

let rec simplify_subs xs vs ans = 
  let (vs1,subs,rest) = extr_subs xs vs [] [] in
  if subs==[] then (ans,xs)
  else simplify_subs rest vs1 (subs@ans)

let apply_subs_sv s t =
  try
    let (fr,nt) = List.find (fun (f1,_) -> eq_spec_var f1 t) s in
    nt
  with _ -> t

let rec norm_subs subs =
  match subs with
  | [] -> []
  | (fr,t)::xs -> 
    let new_s = norm_subs xs in
    (fr,apply_subs_sv new_s t)::new_s

let is_emp_bag pf rel_vars = match pf with
  | BForm ((pf,_),_) ->
    begin
      match pf with
      | Eq (Var (x,_), Bag ([],_), _)
      | Eq (Bag ([],_), Var (x,_), _) -> mem_svl x rel_vars
      | _ -> false
    end
  | _ -> false

let sum_of_int_lst lst = List.fold_left (+) 0 lst

let rec no_of_cnts f = match f with
  | BForm _ -> if isConstTrue f || is_RelForm f then 0 else 1
  | And (f1,f2,_) -> no_of_cnts f1 + no_of_cnts f2
  | Or (f1,f2,_,_) -> no_of_cnts f1 + no_of_cnts f2
  | AndList fs -> sum_of_int_lst (List.map (fun (_,fml) -> no_of_cnts fml) fs)
  | Not (f,_,_) -> no_of_cnts f
  | Exists (_,f,_,_) -> no_of_cnts f
  | Forall (_,f,_,_) -> no_of_cnts f

let rec remove_red_primed_vars f = match f with
  | BForm _ -> f
  | Or (f1,f2,l,p)-> Or (remove_red_primed_vars f1, remove_red_primed_vars f2, l, p)
  | And (f1,f2,p) -> And (remove_red_primed_vars f1, remove_red_primed_vars f2, p)
  | Not (f,l,p) -> Not (remove_red_primed_vars f, l, p)
  | AndList fs -> AndList (List.map (fun (l,c) -> (l, remove_red_primed_vars c)) fs)
  | Forall (v,f,l,p) -> 
    let new_f = remove_red_primed_vars f in
    let new_f = remove_red_primed_als new_f in
    let vars = fv new_f in
    if mem_svl v vars then Forall (v, new_f, l, p)
    else new_f
  | Exists (v,f,l,p) -> 
    let new_f = remove_red_primed_vars f in
    let new_f = remove_red_primed_als new_f in
    let vars = fv new_f in
    if mem_svl v vars then Exists (v, new_f, l, p)
    else new_f

and remove_red_primed_als f = match f with
  | BForm ((Eq(Var(v1,_),Var(v2,_),p),_),_) -> 
    if to_primed v1 = to_primed v2 then mkTrue p else f
  | BForm ((RelForm(sv,es,p),o1),o2) ->
    let es = List.map remove_red_primed_exp es in
    BForm ((RelForm(sv,es,p),o1),o2)
  | BForm _ -> f
  | Or (f1,f2,l,p)-> mkOr (remove_red_primed_als f1) (remove_red_primed_als f2) l p
  | And (f1,f2,p) -> mkAnd (remove_red_primed_als f1) (remove_red_primed_als f2) p
  | Not (f,l,p) -> Not (remove_red_primed_als f, l, p)
  | AndList fs -> AndList (List.map (fun (l,c) -> (l, remove_red_primed_als c)) fs)
  | Forall (v,f,l,p) -> Forall (v, remove_red_primed_als f, l, p)
  | Exists (v,f,l,p) -> Exists (v, remove_red_primed_als f, l, p)

(* Just a temp patch *)
and remove_red_primed_exp e = match e with
  | Var (sv,p) -> Var (to_unprimed sv,p)
  | _ -> e

let rec andl_to_and f = match f with
  | BForm _ -> f
  | Or (f1,f2,l,p)-> Or (andl_to_and f1, andl_to_and f2, l, p)
  | And (f1,f2,p) -> And (andl_to_and f1, andl_to_and f2, p)
  | Not (f,l,p) -> Not (andl_to_and f, l, p)
  | Forall (v,f,l,p) -> Forall (v,andl_to_and f, l, p)
  | Exists (v,f,l,p) -> Exists (v, andl_to_and f, l, p)
  | AndList b ->
    let l = List.map (fun (_,c)-> andl_to_and c) b in
    List.fold_left (fun a c-> mkAnd a c no_pos) (mkTrue no_pos) l 

and extractLS_b_formula (bf : b_formula) : b_formula =
  let (pf,_) = bf in
  (match pf with
   | BagIn (sv,e,pos)
   | BagNotIn (sv,e,pos) ->
     let vars = afv e in
     let b = List.exists (fun v -> (name_of_spec_var v) = ls_name) vars in
     if b then bf else mkTrue_b no_pos
   | _ -> mkTrue_b no_pos)

let extractLS_pure_x (f : formula) : formula =
  let rec helper f = 
    match f with
    | BForm (bf, lbl) ->
      let n_bf = extractLS_b_formula bf in
      BForm (n_bf, lbl)
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let vars = fv f in
      let b = List.exists (fun v -> (name_of_spec_var v) = ls_name) vars in
      if (b) then
        let n_f = helper f in
        Not (n_f, lbl, pos)
      else (mkTrue no_pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper f
type tscons_res = 
  | No_cons
  | Can_split (*has tree share constraints but they can be separated*)
  | No_split (*has tree share constraints but can not split*)

let join_res t1 t2 = match t1,t2 with
  | Can_split, Can_split -> Can_split
  | No_cons,_ -> t2
  | _, No_cons -> t1
  | No_split, _ 
  | _, No_split -> No_split

let rec has_e_tscons f = match f with
  | Var (v,_) -> (match type_of_spec_var v with | Tree_sh -> true | _ -> false)
  | Tsconst c -> true
  | Add (e1,e2,_) -> (has_e_tscons e1)||(has_e_tscons e2)
  | _ -> false

let has_e_tscons f = Debug.no_1 "has_e_tscons" !print_exp string_of_bool has_e_tscons f

let has_b_tscons f = match f with 
  | Eq (e1,e2,_) -> if (has_e_tscons e1)|| (has_e_tscons e2) then Can_split else No_cons
  | Neq (e1,e2,_)-> if (has_e_tscons e1)|| (has_e_tscons e2) then No_split else No_cons
  | _ -> No_cons 

let has_b_tscons f =
  let pr f = match f with | No_cons -> "no_cons" | No_split -> "no_split" | Can_split -> "can_split" in
  Debug.no_1 "has_b_tscons" (fun c-> !print_formula (BForm ((c,None),None))) pr has_b_tscons f

let rec has_tscons f =  match f with 
  | BForm ((f,_),_) -> has_b_tscons f
  | Or (f1,f2,_,_)
  | And (f1,f2,_)-> join_res (has_tscons f1)  (has_tscons f2)
  | AndList l -> fold_l_snd_f join_res has_tscons No_cons l 
  | Not (f,_,_)
  | Forall (_,f,_,_) 
  | Exists (_,f,_,_) -> has_tscons f 

let has_tscons f = 
  let pr f = match f with | No_cons -> "no_cons" | No_split -> "no_split" | Can_split -> "can_split" in
  Debug.no_1 "has_tscons" !print_formula pr has_tscons f

let rec tpd_drop_all_perm f = match f with 
  | BForm ((b,_),_) -> if has_b_tscons b = Can_split then mkTrue no_pos else f
  | And (f1,f2,l) -> mkAnd (tpd_drop_all_perm f1) (tpd_drop_all_perm f2) l
  | AndList l -> AndList (map_l_snd tpd_drop_all_perm l)
  | Or (f1,f2,l,p) -> mkOr (tpd_drop_all_perm f1) (tpd_drop_all_perm f2) l p 
  | Not (b,l,p) -> mkNot (tpd_drop_all_perm b) l p 
  | Forall (s,f,l,p) -> mkForall [s] (tpd_drop_all_perm f) l p 
  | Exists (v,f,l,p) -> 
    if (type_of_spec_var v)=Tree_sh then tpd_drop_all_perm f
    else Exists (v, tpd_drop_all_perm f, l,p)


let rec tpd_drop_perm f = match f with 
  | BForm ((b,_),_) -> if has_b_tscons b = Can_split then mkTrue no_pos else f
  | And (f1,f2,l) -> mkAnd (tpd_drop_perm f1) (tpd_drop_perm f2) l
  | AndList l -> AndList (map_l_snd tpd_drop_perm l)
  | Or _ -> report_error no_pos ("tpd_drop_perm: to_dnf has failed "^(!print_formula f))
  | Not (b,l,p) -> mkNot (tpd_drop_perm b) l p 
  | Forall (s,f,l,p) -> mkForall [s] (tpd_drop_perm f) l p 
  | Exists (v,f,l,p) -> if (type_of_spec_var v)=Tree_sh then tpd_drop_perm f
    else Exists (v, tpd_drop_perm f, l,p)

let tpd_drop_perm f = Debug.no_1 "tpd_drop_perm" !print_formula !print_formula tpd_drop_perm f

let rec tpd_drop_nperm f = match f with 
  | BForm ((b,_),_) -> if has_b_tscons b = Can_split then [b] else []
  | And (f1,f2,l) -> tpd_drop_nperm f1 @ tpd_drop_nperm f2 
  | AndList l -> fold_l_snd tpd_drop_nperm l 
  | Or _ -> report_error no_pos ("tpd_drop_nperm: to_dnf has failed "^(!print_formula f))
  | Not (b,_,_) ->  if tpd_drop_nperm b=[] then [] else report_error no_pos "tree shares under negation"
  | Forall (_,b,_,_) -> if tpd_drop_nperm b =[] then [] else report_error no_pos "tree shares under forall"
  | Exists _ -> report_error no_pos ("tpd_drop_nperm: to_dnf has failed "^(!print_formula f))

let tpd_drop_nperm f = Debug.no_1 "tpd_drop_nperm" !print_formula (pr_list (fun c-> !print_b_formula (c,None))) tpd_drop_nperm f


let rec get_inst fct v f = match f with
  | BForm ((f,_),_) -> (match f with
      | Eq (Var _ , Var _, _) -> None
      | Eq (e , Var (v1,_), _)
      | Eq (Var (v1,_), e, _)-> if eq_spec_var v v1 then fct e else None
      | _ -> None)
  | And (f1,f2,_) -> (match get_inst fct v f1 with
      | None -> get_inst fct v f2 
      | Some v ->  Some v) 
  | AndList l -> List.fold_left (fun a (_,c)-> match a with | None -> get_inst fct v c | Some _ -> a) None l 
  | Not _
  | Forall _
  | Exists _
  | Or _ -> None

let get_inst_tree v f =
  let fct e = match e with
    | Tsconst (t,_) -> Some t
    | _ -> None in
  get_inst fct v f

let get_inst_int v f = 
  let fct e = match e with
    | IConst (i,_) -> Some i
    | _ -> None in
  get_inst fct v f

let is_term pf =
  match pf with
  | LexVar _ -> true
  | _ -> false

let is_term f =
  match f with
  | BForm ((bf,_),_) -> is_term bf
  | _ -> false

let is_TermR ann = 
  match ann with
  | TermR _ -> true
  | _ -> false

let is_TermR_pf pf =
  match pf with
  | LexVar t_info -> is_TermR t_info.lex_ann
    (* begin                       *)
    (*   match t_info.lex_ann with *)
    (*   | TermR _ -> true         *)
    (*   | _ -> false              *)
    (* end                         *)
  | _ -> false

let is_TermR_formula f = 
  match f with
  | BForm ((bf,_),_) -> is_TermR_pf bf
  | _ -> false

let is_rel_assume rt = match rt with
  | RelAssume _ -> true
  | _ -> false

let is_rel_defn rt = match rt with
  | RelDefn _ -> true
  | _ -> false

let add_conj x rs pos =
  List.map (fun y -> And (x,y,pos)) rs

let rec dist_conj xs ys pos =
  let r_xs = List.map (fun x -> add_conj x ys pos) xs in
  List.concat r_xs

let distr_d ls rs pos =
  match ls with
  | [x] ->
    (match rs with
     | [y] -> [And(x,y,pos)]
     | _ -> add_conj x rs pos
    )
  | _ -> 
    (match rs with
     | [y] -> add_conj y ls pos 
     | _ -> dist_conj ls rs pos
    )
(*
distribute_disjuncts@17
distribute_disjuncts inp1 : x=null & r=v & ((x=null & ZInfinity=m) | x!=null)
distribute_disjuncts@17 EXIT out : (x=null & r=v & x!=null) | (x=null & r=v & x=null & ZInfinity=m)
*)
(* let distribute_disjuncts (f:formula) : formula = *)
(*   let rec helper f = *)
(*     let f_f f =  *)
(*     	(match f with *)
(*     	| And(l,r,p) ->  *)
(*               let l2= split_disjunctions (helper l) in *)
(*               let r2= split_disjunctions (helper r) in *)
(*               let ls= distr_d l2 r2 p in *)
(*               (\* join_disjunctions ls *\) *)
(*               Some (disj_of_list ls p) *)
(*         (\* | AndList _ -> report_error no_pos "met an AndList" *\) *)
(*     	| _ -> Some f) *)
(*     in *)
(*     let f_bf bf = Some bf in *)
(*     let f_e e = Some e in *)
(*     map_formula f (f_f,f_bf,f_e) *)
(*   in helper f *)

(* let distribute_disjuncts (f:formula) : formula = *)
(*   let pr = !print_formula in *)
(*   Debug.no_1 "distribute_disjuncts" pr pr distribute_disjuncts f *)

(*
deep_split_disjuncts@4
deep_split_disjuncts inp1 : x=null & r=v & ((x=null & m=\inf(ZInfinity)) | x!=null)
deep_split_disjuncts@4 EXIT out :[ x=null & r=v & x=null & m=\inf(ZInfinity), x=null & r=v & x!=null]
*)
let deep_split_disjuncts (f:formula) : (bool * formula list) =  
  let disj_inside_andlist = ref false in
  let rec helper f =
    let f_f f =
      let () = print_endline "deep_split_disjuncts" in 
      (match f with
       | Or(l,r,_,p) -> 
         let l2= helper l in
         let r2= helper r in
         (* join_disjunctions ls *)
         Some (l2@r2)
       | And(l,r,p) -> 
         let l2= (helper l) in
         let r2= (helper r) in
         let ls= distr_d l2 r2 p in
         (* join_disjunctions ls *)
         Some (ls)
       | AndList(ls) -> 
         (* checks for disjs inside AndList *)
         let l2= List.map (fun (l,f) -> helper f) ls in
         let k = List.exists (fun f ->(List.length f)>1) l2 in
         if k then disj_inside_andlist := true;
         Some([f])
       (* currently do not split inside AndList *)
       (* | AndList _ -> report_error no_pos "met an AndList" *)
       | _ -> Some [f])
    in
    let f_bf bf = Some [] in
    let f_e e = Some [] in
    fold_formula f (f_f,f_bf,f_e) List.concat
  in
  let res =
    if !Globals.deep_split_disjuncts
    then helper f
    else [f]           
  in
  (!disj_inside_andlist || List.length res>1, res)

(* let deep_split_disjuncts (f:formula) : formula list = *)

(* let deep_split_disjuncts (f:formula) : formula list = *)
(*   Gen.Profiling.no_1 "INF-deep-split" deep_split_disjuncts f *)

let split_disjunctions_deep_sp (f:formula) : bool * (formula list) =
  (* split_disjunctions(distribute_disjuncts f) *)
  deep_split_disjuncts f

let split_disjunctions_deep_sp (f:formula) : (bool * formula list) =
  let pr = !print_formula in
  Debug.no_1 "split_disjunctions_deep" pr (pr_pair string_of_bool (pr_list pr)) split_disjunctions_deep_sp f

(* TODO WN : improve efficiency of distribute_disjuncts *)
let split_disjunctions_deep (f:formula) : formula list =
  (* split_disjunctions(distribute_disjuncts f) *)
  let (_,ans) = deep_split_disjuncts f in ans

let split_disjunctions_deep (f:formula) : formula list =
  let pr = !print_formula in
  (* Debug.no_1 "split_disjunctions_deep" pr (pr_list pr) *) split_disjunctions_deep f

let drop_exists ?(rename_flag=true) (f:formula) :formula = 
  let rec helper f =
    let f_f f = 
      match f with
      | Exists(qid,qf,fl,pos) -> 
            if rename_flag then
              let fresh_fr = fresh_spec_vars [qid] in
              let st = List.combine [qid] fresh_fr in
              let rename_exist_vars  = subst st qf in
              Some((helper rename_exist_vars))
            else Some(helper qf)
      | And _ | AndList _ | Or _  -> None
      | Not _ | Forall _ | BForm _ -> Some(f)
    in
    let f_bf bf = Some bf in
    let f_e e = Some e in
    map_formula f (f_f,f_bf,f_e)
  in helper f

let drop_exists ?(rename_flag=true) (f:formula) :formula =
  let pr = !print_formula in 
  Debug.no_1 "drop_exists_pure" pr pr (drop_exists ~rename_flag:rename_flag) f 

let add_prefix_to_spec_var prefix (sv : spec_var) = match sv with
  | SpecVar (t,n,p) -> SpecVar (t,prefix^n,p)

let fv_wo_rel_r rel = match rel with
  | BForm((RelForm (_, args, _),_),_) -> 
    remove_dups_svl (List.concat (List.map afv args))
  | _ -> report_error no_pos "fv_wo_rel_r: expected RelForm"

let get_rel_args_pformula pf= match pf with
  | RelForm (_, el, _) -> (List.fold_left List.append [] (List.map afv el))
  | _ -> []

let get_rel_args_bformula (pf, _) = get_rel_args_pformula pf

let get_rel_args_x f0=
  let rec helper f=
    match f with
    | BForm (bf, _) -> (get_rel_args_bformula bf)
    | And (f1, f2, _) ->  ((helper f1)@(helper f2))
    | AndList b -> List.fold_left (fun ls (_, p) -> ls@(helper p)) [] b
    | Or (f1, f2, _, _) ->  (helper f1)@(helper f2)
    | Not (p, _, _) ->  helper p
    | Forall (_, p, _, _) -> helper p
    | Exists (_, p, _, _) -> helper p
  in
  helper f0

let get_rel_args f0=
  Debug.no_1 "get_rel_args" !print_formula !print_svl
    (fun _ -> get_rel_args_x f0) f0

let subst_rel_args_x p eqs rel_args=
  let filter_fn ls (sv1,sv2)=
    let b1 = mem_svl sv1 rel_args in
    let b2 = mem_svl sv2 rel_args in
    match b1,b2 with
    | true,false -> ls@[(sv1,sv2)]
    | false,true -> ls@[(sv2,sv1)]
    | _ -> ls
  in
  let eqs1= List.fold_left filter_fn [] eqs in
  subst eqs1 p

let subst_rel_args p eqs rel_args=
  Debug.no_2 "subst_rel_args" !print_formula !print_svl !print_formula
    (fun _ _ -> subst_rel_args_x p eqs rel_args) p rel_args

let get_eqs_rel_args_x p eqs rel_args pos=
  let filter_fn (sv1,sv2)=
    (mem_svl sv1 rel_args) ||
    ( mem_svl sv2 rel_args)
  in
  let eqs1= List.filter filter_fn eqs in
  List.fold_left (fun p1 (sv1,sv2) ->
      let p2 = mkEqVar sv1 sv2 pos in
      mkAnd p1 p2 pos)
    (mkTrue pos) eqs1

let get_eqs_rel_args p eqs rel_args pos=
  Debug.no_2 "get_eqs_rel_args" !print_formula !print_svl !print_formula
    (fun _ _ -> get_eqs_rel_args_x p eqs rel_args pos) p rel_args



(* check for x=y & x!=y and mark as unsat assumes that disjunctions are all split using deep_split *)
let is_sat_eq_ineq (f : formula) : bool =
  let b =
    (*check if eqs contradict with ineqs *)
    if (isConstFalse f) then true
    else
      (* create a single eset for pure formula*)
      let m_aset = build_eqmap_at_toplevel (* find_eq_all *) f in
      let p_aset = pure_ptr_equations f in
      let p_aset = EMapSV.build_eset p_aset in
      let m_aset = EMapSV.merge_eset p_aset m_aset in
      if is_false_eq m_aset then true else
        (* parition the eset *)
        let m_apart = EMapSV.partition m_aset in
        let flist = split_conjunctions f in
        List.exists (fun pf ->
            match pf with 
            | BForm(bf,_) -> 
              (match (get_bform_neq_args_with_const bf) with
               | Some (v1, v2) -> List.exists (fun ls -> 
                   Gen.BList.subset_eq eq_spec_var [v1; v2] ls) m_apart  
               | None -> false)
            | _ -> false
          ) flist in (not b)

let extractLS_pure (pf : formula) : formula = 
  Debug.no_1 "extractLS_pure" !print_formula !print_formula 
    extractLS_pure_x pf

(*Currently, only remove constraints
  that directly related to lockset
  Do not consider transitivity*)
let removeLS_b_formula (bf : b_formula) : b_formula =
  let (pf,st) = bf in
  (match pf with
   | BagIn (sv,e,pos)
   | BagNotIn (sv,e,pos) ->
     let vars = afv e in
     let b = List.exists (fun v -> (name_of_spec_var v) = ls_name || (name_of_spec_var v) = lsmu_name) vars in
     if b then mkTrue_b no_pos else  bf
   | Eq (e1, e2, pos) (* these two could be arithmetic or pointer or bag or list *)
   | Neq (e1, e2, pos) ->
     let vars1 = afv e1 in
     let vars2 = afv e2 in
     let b = List.exists (fun v -> (name_of_spec_var v) = ls_name || (name_of_spec_var v) = lsmu_name) (vars1@vars2) in
     if b then mkTrue_b no_pos else  bf
   (* | VarPerm (vp_ann,svl,pos) ->                                                                                                                                                  *)
   (*     let nsvl =  List.filter (fun v -> name_of_spec_var v <> Globals.ls_name && name_of_spec_var v <> Globals.lsmu_name && name_of_spec_var v <> Globals.waitlevel_name) svl in *)
   (*     if (nsvl=[]) then mkTrue_b no_pos else                                                                                                                                     *)
   (*     (VarPerm (vp_ann,nsvl,pos),st)                                                                                                                                             *)
   | BagSub (e1,e2,pos) -> bf (*TO CHECK there 3 cases*)
   | BagMin (sv1,sv2,pos) -> bf
   | BagMax (sv1,sv2,pos) -> bf
   | _ -> bf)

(*remove lockset constraints from a formula*)
let removeLS_pure_x (pf : formula) : formula =
  let rec helper f = 
    match f with
    | BForm (bf, lbl) ->
      let n_bf = removeLS_b_formula bf in
      BForm (n_bf, lbl)
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let n_f = helper f in
      Not (n_f, lbl, pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper pf

(*remove lockset constraints from a formula*)
(*Currently, only remove constraints
  that directly related to lockset
  Do not consider transitivity*)
let removeLS_pure (pf : formula) : formula = 
  Debug.no_1 "removeLS_pure" !print_formula !print_formula 
    removeLS_pure_x pf

let existSV (v:spec_var) (svl:spec_var list) = List.exists (fun x -> eq_spec_var v x) svl

let remove_svl_b_formula (bf : b_formula) (svl:spec_var list) : b_formula =
  let (pf,st) = bf in
  (match pf with
   | BVar (sv,pos) ->
     let b = existSV sv svl in
     if b then mkTrue_b no_pos else  bf
   | BagIn (sv,e,pos)
   | BagNotIn (sv,e,pos) ->
     let vars = afv e in
     let b = List.exists (fun v -> existSV v svl) vars in
     if b then mkTrue_b no_pos else  bf
   | Lt (e1, e2, pos)
   | Lte (e1, e2, pos)
   | Gt (e1, e2, pos)
   | Gte (e1, e2, pos)
   | Eq (e1, e2, pos) (* these two could be arithmetic or pointer or bag or list *)
   | Neq (e1, e2, pos) ->
     let vars1 = afv e1 in
     let vars2 = afv e2 in
     let b = List.exists (fun v -> existSV v svl) (vars1@vars2) in
     if b then mkTrue_b no_pos else  bf
   (* | VarPerm (vp_ann,svl,pos) ->                               *)
   (*     let nsvl =  List.filter (fun v -> existSV v svl) svl in *)
   (*     if (nsvl=[]) then mkTrue_b no_pos else                  *)
   (*     (VarPerm (vp_ann,nsvl,pos),st)                          *)
   | _ -> bf (*assume the rest does not contain constraints on svl*)
  )

(*remove constraints related to a list of spec vars*)
let drop_svl_pure (pf : formula) (svl:spec_var list) : formula =
  let rec helper f = 
    match f with
    | BForm (bf, lbl) ->
      let n_bf = remove_svl_b_formula bf svl in
      BForm (n_bf, lbl)
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let n_f = helper f in
      Not (n_f, lbl, pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper pf

(*
Before sending to provers,
translate l1=l2 into l1=l2 & level(l1)=level(l2)
*)
let translate_level_eqn_b_formula (bf:b_formula) : formula =
  let pf,sth = bf in
  (match pf with
   | Eq (e1,e2,pos) ->
     (match (e1, e2) with
      | (Var (sv1,pos1), Var (sv2,pos2)) ->
        if (type_of_spec_var sv1) = lock_typ then
          let mu1 = Level (sv1,pos1) in (* l1.mu *)
          let mu2 = Level (sv2,pos2) in (* l2.mu *)
          let npf = Eq (mu1,mu2,pos) in
          let nf = BForm ((npf,sth),None) in
          let f = BForm (bf,None) in
          And (f,nf,pos)
        else
          BForm (bf,None)
      | _ ->  BForm (bf,None))
   |_ -> BForm (bf,None)
  )

(*
Before sending to provers,
translate l1=l2 into l1=l2 & level(l1)=level(l2)
*)
let translate_level_eqn_pure_x (pf : formula) : formula =
  let rec helper f =
    match f with
    | BForm (bf, lbl) ->
      let nf = translate_level_eqn_b_formula bf in
      nf
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let n_f = helper f in
      Not (n_f, lbl, pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper pf

(*
Before sending to provers,
translate l1=l2 into l1=l2 & level(l1)=level(l2)
*)
let translate_level_eqn_pure (pf : formula) : formula =
  Debug.no_1 "translate_level_eqn_pure" !print_formula !print_formula 
    translate_level_eqn_pure_x pf

(*Translate level(l) into l_mu before sending to provers*)
let translate_level_pure_x (pf : formula) : formula =
  let pf = translate_level_eqn_pure pf in
  let trans_exp (e:exp): exp =
    let rec helper e = 
      match e with
      | Level (SpecVar (t,id,p),l) ->
        let nid = id^"_mu" in
        (Var (SpecVar (level_data_typ,nid,p),l))
      | Add (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Add (res1,res2,pos)
      | Subtract (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Subtract (res1,res2,pos)
      | Mult (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Mult (res1,res2,pos)
      | Div (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Div (res1,res2,pos)
      | Max (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Max (res1,res2,pos)
      | Min (e1,e2,pos) ->
        let res1 = helper e1 in
        let res2 = helper e2 in
        Min (res1,res2,pos)
      | TypeCast (ty, e1, pos) ->
        let res1 = helper e1 in
        TypeCast (ty, res1, pos)
      | Bag (exps,pos) -> 
        let nexps = List.map helper exps in
        Bag (nexps,pos)
      | BagUnion (exps,pos) ->
        let nexps = List.map helper exps in
        BagUnion (nexps,pos)
      | BagIntersect (exps,pos) -> 
        let nexps = List.map helper exps in
        BagIntersect (nexps,pos)
      | BagDiff (exp1,exp2,pos) -> 
        let nexp1 = helper exp1 in
        let nexp2 = helper exp2 in
        BagDiff (nexp1,nexp2,pos)
      | _ -> e
    in (helper e)
  in
  let trans_exp_opt e = Some (trans_exp e) in
  let trans_bf e = None in
  let rec helper f =
    match f with
    | BForm (bf, lbl) ->
      let n_bf = transform_b_formula (trans_bf,trans_exp_opt) bf in
      BForm (n_bf, lbl)
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let n_f = helper f in
      Not (n_f, lbl, pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper pf

(*Translate level(l) into l_mu before sending to provers*)
let translate_level_pure (pf : formula) : formula =
  Debug.no_1 "translate_level_pure" !print_formula !print_formula 
    translate_level_pure_x pf


let level_vars_exp e =
  let rec helper e =
    match e with
    | Var (SpecVar (t,id,pr),pos) ->
      if (t=lock_typ) then [SpecVar (t,id,pr)] else []
    | Level (sv,_) -> [sv]
    | Bag (exps,_)
    | BagUnion (exps,_)
    | BagIntersect (exps,_) ->
      List.concat (List.map helper exps)
    | BagDiff (e1,e2,_) ->
      let vars1 = helper e1 in
      let vars2 = helper e2 in
      vars1@vars2
    | _ -> []
  in helper e

let level_vars_b_formula bf =
  let (pf,il) = bf in
  (match pf with
   | Lt (e1,e2,l) 
   | Lte (e1,e2,l)
   | Gt (e1,e2,l)
   | Gte (e1,e2,l)
   | Eq (e1,e2,l)
   | Neq (e1,e2,l) ->
     let vars1 = level_vars_exp e1 in
     let vars2 = level_vars_exp e2 in
     vars1@vars2
   | BagIn (v,e,l)
   | BagNotIn (v,e,l)->
     level_vars_exp e
   | BagSub _
   | ListIn _
   | ListNotIn _
   | ListAllN _
   | ListPerm _
   | RelForm _
   | ImmRel _
   | LexVar _
   | Frm _
   | BConst _
   | BVar _ 
   | BagMin _ 
   | SubAnn _
   | EqMax _
   | EqMin _
   (* | VarPerm _ *)
   | XPure _
   | BagMax _ -> []
  )

(*for each level(l), add a constraint level(l) > 0*)
let infer_level_pure_x (pf : formula) : formula =
  let rec helper f =
    match f with
    | BForm (bf, lbl) ->
      let vars = level_vars_b_formula bf in
      if vars=[] then f else
        List.fold_left (fun f sv ->
            let level_exp = mkLevel sv no_pos in
            let gt_exp = mkGtExp level_exp (IConst (0,no_pos)) no_pos in
            And (gt_exp,f,no_pos)
          ) f vars
    | And (f1, f2, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      And (n_f1, n_f2, pos)
    | AndList b -> 
      let nf = List.fold_left (fun ls_f (_,f_b) -> 
          let nf = helper f_b in
          And (ls_f, nf, no_pos)
        ) (mkTrue no_pos) b in
      nf
    | Or (f1, f2, lbl, pos) ->
      let n_f1 = helper f1 in
      let n_f2 = helper f2 in
      Or (n_f1, n_f2, lbl, pos)
    | Not (f, lbl, pos) ->
      let n_f = helper f in
      Not (n_f, lbl, pos)
    | Forall (sv, f, lbl, pos) ->
      let n_f = helper f in
      Forall (sv, n_f, lbl, pos)
    | Exists (sv, f, lbl, pos) ->
      let n_f = helper f in
      Exists (sv, n_f, lbl, pos)
  in helper pf

let infer_level_pure (f : formula) : formula =
  Debug.no_1 "infer_level_pure"
    !print_formula !print_formula
    infer_level_pure_x f

(*Attempt to infer constraints on LSMU based on constraints on LS
  For example:
  LS'=LS --infer--> LSMU'=LSMU
  l in LS --infer--> l.mu=v & v in LSMU
*)
let infer_lsmu_pure_x (f:formula) : formula * (spec_var list)=
  if (not !allow_locklevel) then (f,[]) else
    let convert_ls_to_lsmu_exp (e:exp) : exp =
      let rec helper e =
        match e with
        | Var (SpecVar (t,id,p),pos) ->
          if (t = Globals.lock_typ) then
            Level (SpecVar (t,id,p),pos)
          else if (id = ls_name) then
            let nsv = SpecVar (lsmu_typ,lsmu_name,p) in
            Var (nsv,pos)
          else
            let () = print_endline_quiet ("[convert_ls_to_lsmu_exp] Warning: unexpected 2") in
            e
        | Bag (exps,pos) ->
          let nexps = List.map helper exps in
          Bag (nexps,pos)
        | BagUnion (exps,pos) ->
          let nexps = List.map helper exps in
          BagUnion (nexps,pos)
        | BagIntersect (exps,pos) ->
          let nexps = List.map helper exps in
          BagIntersect (nexps,pos)
        | BagDiff (e1,e2,pos) ->
          let ne1 = helper e1 in
          let ne2 = helper e2 in
          BagDiff (ne1,ne2,pos)
        | _ ->
          let () = print_endline_quiet ("[convert_ls_to_lsmu_exp] Warning: unexpected 1") in
          e
      in helper e
    in
    let fct (p:formula) : formula =
      let rec helper p =
        match p with
        | BForm (bf,lbl) -> 
          let pf,sth = bf in
          (match pf with
           | Eq (e1, e2, pos) ->
             let vars1 = afv e1 in
             let vars2 = afv e2 in
             let b = List.exists (fun sv -> (name_of_spec_var sv) = ls_name) (vars1@vars2) in
             if (b) then
               let lsmu_e1 = convert_ls_to_lsmu_exp e1 in
               let lsmu_e2 = convert_ls_to_lsmu_exp e2 in
               let npf = Eq (lsmu_e1, lsmu_e2, pos) in
               let nbf = (npf,sth) in
               let np = BForm (nbf,lbl) in
               And (p,np,pos)
             else BForm (bf,lbl)
           | BagIn (SpecVar (t,id,pr),e,pos) ->
             (* l in LS --> exists mu_123. mu_123 = level(l) & mu_123 in LSMU*)
             if (t=lock_typ) then
               (* let ne =  convert_ls_to_lsmu_exp e in *)
               let level_var = mkLevelVar Unprimed in
               let fresh_var = fresh_spec_var level_var in
               let fresh_var_exp = Var (fresh_var,pos) in
               let eq_f = mkEqExp fresh_var_exp (Level (SpecVar (t,id,pr),pos)) pos in (*mu_123=level(l)*)
               let lsmu_exp = Var (mkLsmuVar pr,pos) in
               let in_f = mkBagInExp fresh_var lsmu_exp pos in (*mu_123 in LSMU*)
               let f_and = And (eq_f,in_f,pos) in
               let f_exists = Exists (fresh_var,f_and,None,pos) in
               And (p,f_exists,pos)
             else p
           | BagNotIn (SpecVar (t,id,pr),e,pos) ->
             (* l notin LS --> exists mu_123. mu_123 = level(l) & mu_123 notin LSMU*)
             if (t=lock_typ) then
               (* let ne =  convert_ls_to_lsmu_exp e in *)
               let level_var = mkLevelVar Unprimed in
               let fresh_var = fresh_spec_var level_var in
               let fresh_var_exp = Var (fresh_var,pos) in
               let eq_f = mkEqExp fresh_var_exp (Level (SpecVar (t,id,pr),pos)) pos in (*mu_123=level(l)*)
               let lsmu_exp = Var (mkLsmuVar pr,pos) in
               let in_f = mkBagNotInExp fresh_var lsmu_exp pos in (*mu_123 in LSMU*)
               let f_and = And (eq_f,in_f,pos) in
               let f_exists = Exists (fresh_var,f_and,None,pos) in
               And (p,f_exists,pos)
             else p
           | _ -> BForm (bf,lbl)
          )
        | And (f1,f2,pos) ->
          let nf1 = helper f1 in
          let nf2 = helper f2 in
          And (nf1,nf2,pos)
        | AndList ls -> 
          let nls = List.map (fun (lbl,f) ->
              let nf = helper f in
              (lbl,nf)
            ) ls in
          AndList nls
        | Or (f1,f2,lbl,pos) ->
          let nf1 = helper f1 in
          let nf2 = helper f2 in
          Or (nf1,nf2,lbl,pos)
        | Not (f,lbl,pos) ->
          let nf = helper f in
          Not (nf,lbl,pos)
        | Forall (var,f,lbl,pos) ->
          let nf = helper f in
          Forall (var,nf,lbl,pos)
        | Exists (var,f,lbl,pos) ->
          let nf = helper f in
          Exists (var,nf,lbl,pos)
      in helper p
    in
    let nf = fct f in
    let nf = infer_level_pure nf in
    let nf2,evars = split_ex_quantifiers_rec nf in
    (nf2,evars)

(*Attempt to infer constraints on LSMU based on constraints on LS
  For example:
  LS'=LS --infer--> LSMU'=LSMU
  l in LS --infer--> l.mu=v & v in LSMU
*)
let infer_lsmu_pure (f:formula) : formula * (spec_var list) =
  let pr_out = pr_pair !print_formula !print_svl in
  Debug.no_1 "infer_lsmu_pure"
    !print_formula pr_out
    infer_lsmu_pure_x f

(*
Before sending to provers,
translate waitlevel into constraints related to LSMU:

waitlevel>x ==define==> (ls={} => x<0) & (ls!={} => exist v. v in LSMU & v>x)

waitlevel<x ==define==> (ls={} => x>0) & (ls!={} => forall v. v in LSMU => v<x)

waitlevel=x ==def== (LS={} => x=0)
  & (LS!={} => (forall level in LSMU. level<=x) & (exist level in LSMU. level=x)

In other words,
waitlevel=x ==def== (LS={} => x=0)
  & (LS!={} => (forall level in LSMU. level<=x) & (x in LSMU)

or

waitlevel=x ==def== (not LS={} | x=0)
  & ((not LS!={}) | ((forall level in LSMU. level<=x) & (x in LSMU))

*)
(*translate constraints
  bf: define operator
  pr: Primed or Unprimed
*)

(*TODO: may want to extend it to <=, >, >= *)
let rec translate_waitlevel_p_formula_x (bf : b_formula) (x:exp) (pr:primed) pos : formula =
  (*forall v. v in LSMU & v>0*)
  (* let level_var = mkLevelVar Unprimed in *)
  (* let fresh_var = fresh_spec_var level_var in *)
  (* let fresh_var_exp = Var (fresh_var,pos) in *)
  (* let lsmu_exp = Var (mkLsmuVar pr,pos) in *)
  (* let f1 = mkBagInExp fresh_var lsmu_exp pos in (\*v in LSMU*\) *)
  (* let f_gt_zero = mkGtExp fresh_var_exp (IConst (0,pos)) pos in (\*v>0*\) *)
  (* let f = And (f1,f_gt_zero,pos) in (\*v in LSMU and v>0*\) *)
  (* let init = Forall (fresh_var,f,None,pos) (\*forall v. v in LSMU & v>0*\) in *)
  let pf,sth = bf in
  (match pf with
   (*Currently, we only consider two types on constraints
     on waitlevel: < and = and waitlevel should be on LHS*)
   | Lt _ ->
     (* WRONG: waitlevel< x ==define==> forall v. v in LSMU => v>0 & v<x*)
     (* CORRECT: waitlevel<x ==define==> (ls={} => x>0) & (ls!={} => forall v. v in LSMU => v<x)
        or
        (ls!={} | x>0) & (ls={} | (forall v. v in LSMU => v<x))
        or
        (ls!={} | x>0) & (ls={} | (forall v. v notin LSMU | v<x))
     *)
     let level_var = mkLevelVar Unprimed in
     let fresh_var = fresh_spec_var level_var in
     let fresh_var_exp = Var (fresh_var,pos) in
     let lsmu_exp = Var (mkLsmuVar pr,pos) in
     let ls_exp = Var (mkLsmuVar pr,pos) in (*TO CHECK*)
     (*---------------*)
     let f_neq = mkNeqExp ls_exp (mkEmptyBag pos) pos in (* LS!={} *)
     let f_gt_zero = mkGtExp x (IConst (0,pos)) pos in (*x>0*)
     let f1 = Or (f_neq,f_gt_zero,None,pos) in (* ls!={} | x>0 *)
     (*---------------*)
     let f_eq_ls = mkEqExp ls_exp (mkEmptyBag pos) pos in (* LS={} *)

     let f21 = mkBagNotInExp fresh_var lsmu_exp pos in (*v notin LSMU*)
     let f22 = mkLtExp fresh_var_exp x pos in (*v<x*)
     let f2_or = Or (f21,f22,None,pos) in (* v notin LSMU | v<x *)
     let f2_forall = Forall (fresh_var,f2_or,None,pos) in (*forall v. v in LSMU => v<x* or forall v. v notin LSMU | v<x *)
     let f2 = Or (f_eq_ls,f2_forall,None,pos) in (* (ls={} | (forall v. v notin LSMU | v<x)) *)
     And (f1,f2,pos)
   | Eq _ ->
     (* waitlevel=x ==def== (not LS={} | x=0) *)
     (*   & ((not LS!={}) | ((forall level in LSMU. level<=x) & (x in LSMU)) *)
     (* OR *)
     (* waitlevel=x ==def== (LS!={} | x=0) *)
     (*   & ((LS={}) | ((forall level. level in LSMU => level<=x) & (x in LSMU)) *)
     (* OR *)
     (* waitlevel=x ==def== (LS!={} | x=0) *)
     (*   & ((LS={}) | ((forall level. level notin LSMU | level<=x) & (x in LSMU)) *)

     let level_var = mkLevelVar Unprimed in
     let fresh_var = fresh_spec_var level_var in
     let fresh_var_exp = Var (fresh_var,pos) in
     let lsmu_exp = Var (mkLsmuVar pr,pos) in
     let ls_exp = Var (mkLsmuVar pr,pos) in (*TO CHECK*)
     (*---------------*)
     let f_neq = mkNeqExp ls_exp (mkEmptyBag pos) pos in (* LS!={} *)
     let f_eq_zero = mkEqExp x (IConst (0,pos)) pos in (*x=0*)
     let f1 = Or (f_neq,f_eq_zero,None,pos) in
     (*---------------*)
     let f_eq_ls = mkEqExp ls_exp (mkEmptyBag pos) pos in (* LS={} *)

     let f_notin_lsmu = mkBagNotInExp fresh_var lsmu_exp pos in (*v notin LSMU*)
     let f_lte = mkLteExp fresh_var_exp x pos in (*v<=x*)
     let f_or = Or (f_notin_lsmu,f_lte,None,pos) in
     let f221 = Forall (fresh_var,f_or,None,pos) in 
     (*forall v. v in LSMU => v<=x*) (*forall v. v notin LSMU | v<=x*)
     (***************************)
     (* let level_var2 = mkLevelVar Unprimed in *)
     (* let fresh_var2 = fresh_spec_var level_var in *)
     (* let fresh_var2_exp = Var (fresh_var2,pos) in (\*v2*\) *)
     (* let f_in_lsmu = mkBagInExp fresh_var2 lsmu_exp pos in (\*v2 in LSMU*\) *)
     (* let f_eq_exist = mkEqExp fresh_var2_exp x pos in (\*v=x*\) *)
     (* let f_and = And (f_in_lsmu,f_eq_exist,pos) in *)
     (* let f_exists = Exists (fresh_var2,f_and,None,pos) in *)
     (*Exists v2 . v2 in LSMU & v2=x*)
     (***************************)
     (*Note: Exists v2 . v2 in LSMU & v2=x SIMILAR TO x in LSMU *)
     (***************************)
     (* let f222 = f_exists in *)
     let f222 = (match x with (*x in LSMU*)
         | Var (sv,posx) ->
           mkBagInExp sv lsmu_exp pos
         | Level (sv,posx) ->
           (*level(x) in LSMU ==> exists mu_123. mu_123=level(x) & mu_123 in LSMU*)
           let level_var = mkLevelVar Unprimed in
           let fresh_var = fresh_spec_var level_var in (*mu_123*)
           let fresh_var_exp = Var (fresh_var,pos) in
           let eq_f = mkEqExp fresh_var_exp x pos in (*mu_123=level(x)*)
           let in_f = mkBagInExp fresh_var lsmu_exp pos in (*mu_123 in LSMU*)
           let f_and = And (eq_f,in_f,pos) in
           let f_exists = Exists (fresh_var,f_and,None,pos) in
           f_exists
         (* mkBagLInExp sv lsmu_exp pos *)
         | _ -> Error.report_error { Error.error_loc = pos; Error.error_text = "translate_waitlevel_p_formula: unexpected operator: only expecting integer value in waitlevel formulae" ^ (!print_exp x);})
     in
     let f22 = And (f221,f222,pos) in
     let f2 = Or (f_eq_ls,f22,None,pos) in
     And (f1,f2,pos)
   | Gt _ ->
     (* waitlevel>x ==define==> (ls={} => x<0) & (ls!={} => exist v. v in LSMU & v>x)
        or
        (ls!={} | x<0) & (ls={} | (exist v. v in LSMU & v>x))
     *)
     let level_var = mkLevelVar Unprimed in
     let fresh_var = fresh_spec_var level_var in
     let fresh_var_exp = Var (fresh_var,pos) in
     let lsmu_exp = Var (mkLsmuVar pr,pos) in
     let ls_exp = Var (mkLsmuVar pr,pos) in (*TO CHECK*)
     (*---------------*)
     let f_neq = mkNeqExp ls_exp (mkEmptyBag pos) pos in (* LS!={} *)
     let f_lt_zero = mkLtExp x (IConst (0,pos)) pos in (*x<0*)
     let f1 = Or (f_neq,f_lt_zero,None,pos) in (* ls!={} | x<0 *)
     (*---------------*)
     let f_eq_ls = mkEqExp ls_exp (mkEmptyBag pos) pos in (* LS={} *)
     let f21 = mkBagInExp fresh_var lsmu_exp pos in (*v in LSMU*)
     let f22 = mkGtExp fresh_var_exp x pos in (*v>x*)
     let f2_and = And (f21,f22,pos) in (* v in LSMU & v<x *)
     let f2_exists = Exists (fresh_var,f2_and,None,pos) in (*exists v. v in LSMU & v>x *)
     let f2 = Or (f_eq_ls,f2_exists,None,pos) in (* (ls={} | (exist v. v in LSMU & v>x) *)
     And (f1,f2,pos) (* (ls!={} | x<0) & (ls={} | (exist v. v in LSMU & v>x)) *)
   | _ -> Error.report_error { Error.error_loc = pos; Error.error_text = "translate_waitlevel_p_formula: unexpected operator: only expecting <, > and = in waitlevel formulae";}
  )

and translate_waitlevel_p_formula (bf : b_formula) (x:exp) (pr:primed) pos : formula =
  Debug.no_2 "translate_waitlevel_p_formula" !print_b_formula !print_exp !print_formula
    ( fun _ _ -> translate_waitlevel_p_formula_x bf x pr pos) bf x

and translate_waitlevel_b_formula_x (bf:b_formula) : formula =
  let rec helper bf =
    let pf,sth = bf in
    (match pf with
     (*Currently, we only consider two types on constraints
       on waitlevel: < and = and waitlevel should be on LHS*)
     (*BASE CASE*)
     | Gt (e1,e2,pos)
     | Lt (e1,e2,pos)
     | Eq (e1,e2,pos) ->
       (match e1 with
        | Var (sv1,pos1)->
          if (name_of_spec_var sv1 = Globals.waitlevel_name) then
            (match e2 with
             | Var (sv2,pos2) -> 
               if (name_of_spec_var sv2 = Globals.waitlevel_name) then
                 (*waitlevel'=waitlevel ==> exist x: waitlevel = x & waitlevel'= x*)
                 (*waitlevel'<waitlevel ==> exist x: waitlevel < x & waitlevel'= x*)
                 (*waitlevel'>waitlevel ==> exist x: waitlevel > x & waitlevel'= x*)
                 let level_var = mkLevelVar Unprimed in
                 let fresh_var = fresh_spec_var level_var in
                 let x_exp = Var (fresh_var,pos) in
                 match pf with
                 | Eq (e1,e2,pos) ->
                   (*waitlevel'=waitlevel ==> exist x: waitlevel = x & waitlevel'= x*)
                   (*translate waitlevel = x*)
                   let nf1 = translate_waitlevel_p_formula bf x_exp (primed_of_spec_var sv1) pos in
                   (*translate waitlevel' = x*)
                   let nf2 = translate_waitlevel_p_formula bf x_exp (primed_of_spec_var sv2) pos in
                   let nf = And (nf1,nf2,pos) in
                   (Exists (fresh_var,nf,None,pos))
                 | Lt (e1,e2,pos) ->
                   (*waitlevel'<waitlevel ==> exist x: waitlevel < x & waitlevel'= x*)
                   (*translate waitlevel < x*)
                   let nf1 = translate_waitlevel_p_formula bf x_exp (primed_of_spec_var sv1) pos in
                   (*translate waitlevel' = x*)
                   let nbf = (Eq (e1,e2,pos),sth) in
                   let nf2 = translate_waitlevel_p_formula nbf x_exp (primed_of_spec_var sv2) pos in
                   let nf = And (nf1,nf2,pos) in
                   (Exists (fresh_var,nf,None,pos))
                 | Gt (e1,e2,pos) ->
                   (*This case indeed cannot happen because we
                     have already normalized
                     waitlevel'> waitlevel to waitlevel<waitlevel'*)
                   (*waitlevel'>waitlevel ==> exist x: waitlevel > x & waitlevel'= x*)
                   (*translate waitlevel > x*)
                   let nf1 = translate_waitlevel_p_formula bf x_exp (primed_of_spec_var sv1) pos in
                   (*translate waitlevel' = x*)
                   let nbf = (Eq (e1,e2,pos),sth) in
                   let nf2 = translate_waitlevel_p_formula nbf x_exp (primed_of_spec_var sv2) pos in
                   let nf = And (nf1,nf2,pos) in
                   (Exists (fresh_var,nf,None,pos))
                 | _ -> Error.report_error { Error.error_loc = pos; Error.error_text = "translate_waitlevel_p_formula: this case won't never happen";}
               else
                 let nf = translate_waitlevel_p_formula bf e2 (primed_of_spec_var sv1) pos in
                 nf
             | Level (sv2,pos2) ->
               let nf = translate_waitlevel_p_formula bf e2 (primed_of_spec_var sv1) pos in
               nf
             | _ ->
               let () = print_endline_quiet ("waitlevel should be comparable to only an integer or a locklevelin in formula " ^ (!print_b_formula bf)) in
               BForm (bf,None)
            )
          else
            let vars2 = afv e2 in
            let b = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
            if (b) then
              let () = print_endline_quiet ("waitlevel should not be in RHS of formula " ^ (!print_b_formula bf)) in
              BForm (bf,None)
            else
              BForm (bf,None)
        | _ -> BForm (bf,None)
       )
     | Lte (e1,e2,pos) -> (*e1<=e2 ~= e1<e2 | e1=e2*) (*This might stress mona too much*)
       let fvars1 = afv e1 in
       let fvars2 = afv e2 in
       let b = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) (fvars1@fvars2) in
       if not b then  BForm (bf,None) else
         let tmp_e1 =  mkLtExp e1 e2 pos in (*e1<e2*)
         let tmp_e2 =  mkEqExp e1 e2 pos in (*e1=e2*)
         let tmp_f = Or (tmp_e1,tmp_e2,None,pos) in (*e1<=e2 ~= e1<e2 | e1=e2*)
         let res_f = translate_waitlevel_pure tmp_f in
         res_f
     | Gte (e1,e2,pos) -> (*e1>=e2 ~= e1>e2 | e1=e2*) (*This might stress mona too much*)
       let fvars1 = afv e1 in
       let fvars2 = afv e2 in
       let b = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) (fvars1@fvars2) in
       if not b then  BForm (bf,None) else
         let tmp_e1 =  mkGtExp e1 e2 pos in (*e1>e2*)
         let tmp_e2 =  mkEqExp e1 e2 pos in (*e1=e2*)
         let tmp_f = Or (tmp_e1,tmp_e2,None,pos) in (*e1>=e2 ~= e1>e2 | e1=e2*)
         let res_f = translate_waitlevel_pure tmp_f in
         res_f
     |_ -> BForm (bf,None))
  in (helper bf)

and translate_waitlevel_b_formula (bf:b_formula) : formula =
  Debug.no_1 "translate_waitlevel_b_formula" !print_b_formula !print_formula
    translate_waitlevel_b_formula_x bf

(*First normalize waitlevel into its normal form of 2 types
  waitlevel<x or waitlevel=x*)
and norm_waitlevel_pure (f : formula) : formula =
  let f_e e = Some e in
  let f_b bf: b_formula option =
    let pf,sth = bf in
    let npf = 
      match pf with
      | Lt (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Gt (e2,e1,l)
        else
          pf
      | Lte (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Gte (e2,e1,l)
        else pf
      | Gt (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Lt (e2,e1,l)
        else pf
      | Gte (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Lte (e2,e1,l)
        else pf
      | Eq (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then 
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Eq (e2,e1,l)
        else pf
      | Neq (e1,e2,l) ->
        let vars1 = afv e1 in
        let vars2 = afv e2 in
        let b1 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars1 in
        let b2 = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) vars2 in
        if (not b1 && b2) then 
          (*if waitlevel is on RHS but not on LHS, move it to LHS*)
          Neq (e2,e1,l)
        else pf
      | _ -> pf
    in Some (npf,sth)
  in
  transform_formula ((fun _-> None),(fun _-> None), (fun _-> None),f_b,f_e) f

and contain_level_exp e =
  match e with
  | Level _ -> true
  | _ -> false

and contain_level_b_formula bf =
  let (pf,il) = bf in
  (match pf with	  
   | Lt (e1,e2,l) 
   | Lte (e1,e2,l)
   | Gt (e1,e2,l)
   | Gte (e1,e2,l)
   | Eq (e1,e2,l)
   | Neq (e1,e2,l) ->
     let b1 = contain_level_exp e1 in
     let b2 = contain_level_exp e2 in
     b1||b2
   | BagIn (v,e,l)
   | BagNotIn (v,e,l)->
     contain_level_exp e
   | BagSub _
   | ListIn _
   | ListNotIn _
   | ListAllN _
   | ListPerm _
   | RelForm _
   | ImmRel _
   | LexVar _
   | Frm _ | BConst _
   | BVar _ 
   | BagMin _ 
   | SubAnn _
   | EqMax _
   | EqMin _
   (* | VarPerm _ *)
   | XPure _
   | BagMax _ -> false
  )

and drop_locklevel_pure_x (f : formula) : formula =
  let f_e e = Some e in
  let f_b bf =
    let nbf = if (contain_level_b_formula bf) then mkTrue_b no_pos
      else bf
    in Some nbf
  in
  transform_formula ((fun _-> None),(fun _-> None), (fun _-> None),f_b,f_e) f

and drop_locklevel_pure (f : formula) : formula =
  Debug.no_1 "drop_locklevel_pure" !print_formula !print_formula 
    drop_locklevel_pure_x f

(*Translate waitlevel into constraints before sending to provers*)
and translate_waitlevel_pure_x (pf : formula) : formula =
  let fvars = fv pf in
  let b = List.exists (fun v -> (name_of_spec_var v = Globals.waitlevel_name)) fvars in
  if not b then pf else
    (*First normalize waitlevel into its normal form of 2 types
      waitlevel<x or waitlevel=x*)
    let pf = norm_waitlevel_pure pf in
    let rec helper f =
      match f with
      | BForm (bf, lbl) ->
        let nf = translate_waitlevel_b_formula bf in
        nf
      | And (f1, f2, pos) ->
        let n_f1 = helper f1 in
        let n_f2 = helper f2 in
        And (n_f1, n_f2, pos)
      | AndList b -> 
        let nf = List.fold_left (fun ls_f (_,f_b) -> 
            let nf = helper f_b in
            And (ls_f, nf, no_pos)
          ) (mkTrue no_pos) b in
        nf
      | Or (f1, f2, lbl, pos) ->
        let n_f1 = helper f1 in
        let n_f2 = helper f2 in
        Or (n_f1, n_f2, lbl, pos)
      | Not (f, lbl, pos) ->
        let n_f = helper f in
        Not (n_f, lbl, pos)
      | Forall (sv, f, lbl, pos) ->
        let n_f = helper f in
        Forall (sv, n_f, lbl, pos)
      | Exists (sv, f, lbl, pos) ->
        let n_f = helper f in
        Exists (sv, n_f, lbl, pos)
    in helper pf

(*
Before sending to provers,
translate waitlevel into constraints related to LSMU:

waitlevel<x ==def== forall level in LSMU. level<x
waitlevel'<x ==def== forall level in LSMU'. level<x

waitlevel=x ==def== (LS={} => x=0)
  & (LS!={} => (forall level in LSMU. level<=x) & (exist level in LSMU. level=x)

In other words,
waitlevel=x ==def== (LS={} => x=0)
  & (LS!={} => (forall level in LSMU. level<=x) & (x in LSMU)

or

waitlevel=x ==def== (not LS={} | x=0)
  & ((not LS!={}) | ((forall level in LSMU. level<=x) & (x in LSMU))

*)
and translate_waitlevel_pure (pf : formula) : formula =
  Debug.no_1 "translate_waitlevel_pure" !print_formula !print_formula 
    translate_waitlevel_pure_x pf

(* Strict: do not drop bag vars *)
and drop_bag_formula_weak_x (pf : formula) : formula =
  let f_bf arg bf =
    let pf, lbl = bf in
    (match pf with
     | BagIn _
     | BagNotIn _
     | BagSub _
     | BagMin _
     | BagMax _
     | ListIn _
     | ListNotIn _
     | ListAllN _
     | ListPerm _ -> Some ((mkTrue_p no_pos,lbl),[])
     | Eq (e1, e2, pos)
     | Neq (e1, e2, pos) ->
       if (is_bag_weak e1) || (is_bag_weak e2) || (is_list e1) || (is_list e2) then
         Some ((mkTrue_p no_pos,lbl),[])
       else
         Some (bf,[])
     | _ -> None)
  in
  let f = (nonef2,f_bf,nonef2) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let npf, _ = trans_formula pf arg f f_arg f_comb in
  npf


and drop_bag_formula_weak (pf : formula) : formula =
  Debug.no_1 "drop_bag_formula_weak" !print_formula !print_formula
    drop_bag_formula_weak_x pf

(* Weak: ignore bag vars *)
and is_bag_constraint_weak_x (e: formula) : bool =  
  let f_e e = match e with
    | Bag _
    | BagUnion _
    | BagIntersect _
    | BagDiff _ -> Some true
    | _ -> Some false
  in
  let or_list = List.fold_left (||) false in
  fold_formula e (nonef, is_bag_b_constraint, f_e) or_list

and is_bag_constraint_weak (e: formula) : bool =  
  Debug.no_1 "is_bag_constraint_weak" !print_formula string_of_bool
    is_bag_constraint_weak_x (e: formula)
(*
  Convert: tup2(a1,a2) --> tup2_a1_a2.
  Return: new formula * (tup2_a1_a2, tup2(a1,a2)) list
*)
and translate_tup2_pure_x (pf : formula) : formula * ((spec_var * exp) list) =
  let f_e arg e =
    match e with
    | Tup2 ((e1,e2),l) ->
      let str1 = !print_exp e1 in
      let str2 = !print_exp e2 in
      (*Could generate a new fresh variable instead.
        However, reuse e1,e2 in the new name to
        make it more meaningful to read *)
      let id = "tup2_" ^ str1 ^ "_" ^ str2 in
      let id = remove_blanks id in
      let sv = mk_spec_var id in
      Some (Var (sv,l), [(sv,e)])
    | _ -> None
  in
  let f = (nonef2,nonef2,f_e) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let nfp, ls = trans_formula pf arg f f_arg f_comb in
  (nfp,ls)


and translate_tup2_pure (pf : formula) : formula * ((spec_var * exp) list) =
  let pr1 = pr_list (pr_pair !print_sv !print_exp) in
  let pr_out = pr_pair !print_formula pr1 in
  Debug.no_1 "translate_tup2_pure" !print_formula pr_out
    translate_tup2_pure_x pf

(*
  Convert: A & v1=tup2(a1,a2) |- B & v2=tup2(b1,b2)
  into: A & v1=tup2_a1_a2 & (a1=b1 & a2=b2 => tup2_a1_a2=tup2_b1_b2) |- B & v2=tup2_b1_b2
  or A & v1=tup2_a1_a2 & (a1!=b1 | a2!=b2 | tup2_a1_a2=tup2_b1_b2) |- B & v2=tup2_b1_b2

  For v1=tup2(a1,a2) and v2=tup2(b1,b2), infer the following
  (a1=b1 & a2=b2 => v1=v2) & (a1!=b1 | a2!=b2 => v1!=v2)
*)
and translate_tup2_imply_x (ante : formula) (conseq : formula) : formula * formula =
  let ante, a_ls = translate_tup2_pure ante in
  let conseq, c_ls = translate_tup2_pure conseq in
  let ls = Gen.BList.remove_dups_eq (fun (v1,e1) (v2,e2) -> eq_spec_var v1 v2) (a_ls@c_ls) in
  let translate_one_pair (v1,e1) (v2,e2) : formula =
    match e1,e2 with
    | Tup2 ((a1,a2),_), Tup2 ((b1,b2),_) ->
      (* (a1!=b1 | a2!=b2 | v1=v2) *)
      let f1 = mkNeqExp a1 b1 no_pos in
      let f2 = mkNeqExp a2 b2 no_pos in
      let f3 = mkEqVar v1 v2 no_pos in
      let f12 = mkOr f1 f2 None no_pos in
      let f123 = mkOr f12 f3 None no_pos in
      (* (a1!=b1 | a2!=b2 => v1!=v2) 
         == (a1=b1 & a2=b2) | v1!=v2
      *)
      let ff1 = mkEqExp a1 b1 no_pos in
      let ff2 = mkEqExp a2 b2 no_pos in
      let ff3 = mkNeqVar v1 v2 no_pos in
      let ff12 = mkAnd ff1 ff2 no_pos in
      let ff123 = mkOr ff12 ff3 None no_pos in
      (mkAnd f123 ff123 no_pos)
    | _ -> report_error no_pos ("translate_one_pair: expected Tup2 only\n")
  in
  let pairs = Gen.BList.get_all_pairs ls in
  let new_ante = List.fold_left (fun res (p1,p2) ->
      let p_f = translate_one_pair p1 p2 in
      mkAnd res p_f no_pos) ante pairs
  in
  (new_ante,conseq)

and translate_tup2_imply (ante : formula) (conseq : formula) : formula * formula =
  let pr_out = pr_pair !print_formula !print_formula in
  Debug.no_2 "translate_tup2_imply" !print_formula !print_formula pr_out
    translate_tup2_imply_x ante conseq

(* Check whether the bag v is concrete in the formula pf *)
and is_concrete_bag_pure_x (pf : formula) (v:spec_var) : bool =
  (*Find all logically equal variables of v*)
  let vars = find_closure_pure_formula v pf in
  let f_bf bf =
    let pf, _ = bf in
    (match pf with
     | Eq (e1,e2,pos) ->
       (match e1,e2 with
        | Var (sv,_), Bag (el,_)
        | Bag (el,_), Var (sv,_) ->
          if (Gen.BList.mem_eq eq_spec_var sv vars) then Some true
          else None
        | _ -> None)
     | _ -> None)
  in
  fold_formula pf (nonef, f_bf, nonef) or_list

and is_concrete_bag_pure (pf : formula) (v:spec_var) : bool =
  Debug.no_2 "is_concrete_bag_pure" !print_formula !print_sv string_of_bool
    is_concrete_bag_pure_x pf v
(*
  Identify concrete bag constraints
  Input: B=union(S1,S2) & S1={a} & S2={b}
  Output: [(S1,{a}), (S2,{b})]
*)

and get_concrete_bag_pure_x (pf : formula) : (spec_var * exp list) list =
  let f_bf arg bf =
    let pf, _ = bf in
    (match pf with
     | Eq (e1,e2,pos) ->
       (match e1,e2 with
        | Var (sv,_), Bag (el,_)
        | Bag (el,_), Var (sv,_) -> Some (bf, [sv,el])
        | _ -> Some (bf,[]))
     | _ -> None)
  in
  let f_f arg pf =
    match pf with
    | Or _ -> Some (pf,[])
    | _ -> None
  in
  let f = (f_f,f_bf,nonef2) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let _, ls = trans_formula pf arg f f_arg f_comb in
  ls

and get_concrete_bag_pure (pf : formula) : (spec_var * exp list) list =
  let pr_out = pr_list (pr_pair !print_sv (pr_list !print_exp)) in
  Debug.no_1 "get_concrete_bag_pure" !print_formula pr_out
    get_concrete_bag_pure_x pf

(* and is_concrete_bag_exp e : bool = *)
(*   (match e with *)
(*     | Bag (exps,_) -> *)
(*           List.forall  *)
(*     | _ -> false) *)

(*
  pf: B=union(S1,S2) & S1={a} & S2={b}
  args: [(S1,{a}), (S2,{b})]
  Out: B=bag{a,b} & S1={a} & S2={b}
*)
and apply_concrete_bag_pure_x (f0 : formula) (args: (spec_var * exp list) list): formula =
  (* Check whether x is concrete in f0 given args*)
  let helper_one x =
    (match x with
     | Var (v2,_) ->
       (try
          let vars = find_closure_pure_formula v2 f0 in
          let (_, exps) = List.find (fun (v1,exps) -> Gen.BList.mem_eq eq_spec_var v1 vars) args in
          (*replace v2 by its concrete value*)
          Some exps
        with Not_found -> None)
     | Bag (es,_) -> Some es
     | _ -> None)
  in
  let f_bf arg bf =
    let pf, lbl = bf in
    (match pf with
     | Eq (e1,e2,pos) ->
       (match e1,e2 with (*Also need to support BagIntersect and BagDiff*)
        | Var (sv,l1), BagUnion (el,l2)
        | BagUnion (el,l2), Var (sv,l1) ->
          let rec helper el : (bool * exp list) =
            (match el with
             | [] -> (true, [])
             | x::xs ->
               let nx = helper_one x in
               (match nx with
                | None -> (false,[])
                | Some x2 ->
                  let b,nxs = helper xs in
                  (b,x2@nxs)))
          in
          let flag,nel = helper el in
          if (flag) then
            (*All elements in el are conrete.
              Convert union into a big bag*)
            let npf = Eq (Var (sv,l1),Bag (nel,l2),pos) in
            let nbf = npf, lbl in
            Some (nbf,[]) (*dummy []*)
          else
            (*Failed to concretize*)
            Some (bf,[]) (*dummy []*)
        | Var (sv,l1), BagDiff (e1,e2,l2)
        | BagDiff (e1,e2,l2), Var (sv,l1) ->
          let ne1 = helper_one e1 in
          let ne2 = helper_one e2 in
          (match ne1,ne2 with
           | Some xs1, Some xs2 ->
             (*diff(xs1,xs2) : trust the eqExp_f : TOCHECK *)
             let x = Gen.BList.difference_eq (eqExp_f eq_spec_var) xs1 xs2 in
             let npf = Eq (Var (sv,l1),Bag (x,l2),pos) in
             let nbf = npf, lbl in
             Some (nbf,[]) (*dummy []*)
           | _ ->
             (*Failed to concretize*)
             Some (bf,[])) (*dummy []*)
        | _ -> Some (bf,[]) (*dummy []*)
       )
     | _ -> None)
  in
  let f = (nonef2,f_bf,nonef2) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let nf, _ = trans_formula f0 arg f f_arg f_comb in
  nf

and apply_concrete_bag_pure (pf : formula) (args: (spec_var * exp list) list): formula =
  let pr1 = pr_list (pr_pair !print_sv (pr_list !print_exp)) in
  Debug.no_2 "apply_concrete_bag_pure" !print_formula pr1 !print_formula
    apply_concrete_bag_pure_x pf args

(*
  Attempt to concretize bags constraints, wherever possible.
  E.g.
  B=union(S1,S2) & S1={a} & S2={b}
  ==>
  B=union({a},{b}) & S1={a} & S2={b}
  B={a,b} & S1={a} & S2={b}

  Method: a fixpoint operation over two phases:
  (1) get_concrete_bag_pure
  (2) if fixpoint reached -> stop.
  Otherwise, attemp to do concretization
*)

and concretize_bag_pure_x (pf : formula) : formula =
  let rec helper_loop (pf : formula) (args: (spec_var * exp list) list): formula =
    let ls = get_concrete_bag_pure pf in
    let vs,_ = List.split args in
    let new_vs,_ = List.split ls in
    if (Gen.BList.difference_eq eq_spec_var new_vs vs) =[] then
      pf (* Reach a fixpoint*)
    else
      (*if found new concrete vars --> iterate*)
      let npf = apply_concrete_bag_pure pf ls in
      helper_loop npf ls
  in
  (*Ensure do at least once, e.g. for C=diff({1,2,3},{3,4,5}) *)
  let pf = apply_concrete_bag_pure pf [] in
  helper_loop pf []

and concretize_bag_pure (pf : formula) : formula =
  Debug.no_1 "concretize_bag_pure" !print_formula !print_formula
    concretize_bag_pure_x pf

(* Convert all cyclic(B) into acyclic(B) *)
and from_cyclic_to_acyclic_rel_pure_x (pf : formula) : formula =
  let f_bf arg bf =
    let pf, lbl = bf in
    (match pf with
     | RelForm (SpecVar (t,id,pr),exps,pos) ->
       (*convert*)
       if (id = Globals.cyclic_name) then
         let npf = RelForm (SpecVar (t,Globals.acyclic_name,pr),exps,pos) in 
         Some ((npf,lbl), [])
       else Some (bf, [])
     | _ -> None)
  in
  let f = (nonef2,f_bf,nonef2) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let npf, _ = trans_formula pf arg f f_arg f_comb in
  npf

and from_cyclic_to_acyclic_rel_pure (pf : formula) : formula =
  Debug.no_1 "from_cylic_to_acyclic_rel_pure" !print_formula !print_formula
    from_cyclic_to_acyclic_rel_pure_x pf

(*
  pf: (A & acylic(X) & B)
  rel_name: acylic
  out: (A&B, [acylic(X)])
*)
and extract_rel_pure_x (pf : formula) (rel_name : spec_var): formula * (p_formula list)  =
  let f_bf arg bf =
    let pf, _ = bf in
    (match pf with
     | RelForm (sv,_,pos) ->
       (*extract*)
       if (eq_spec_var sv rel_name) then Some (mkTrue_b pos, [pf])
       else Some (bf, [])
     | _ -> None)
  in
  let f_f arg pf =
    match pf with
    | Or _ ->
      (* let () = print_endline ("[Warning] extract_rel_pure: Or _ found and ignored! ") in *)
      Some (pf,[])
    | _ -> None
  in
  let f = (f_f,f_bf,nonef2) in
  let f_arg = voidf2, voidf2, voidf2 in
  let f_comb = List.concat in
  let arg = () in
  let npf, ls = trans_formula pf arg f f_arg f_comb in
  (npf,ls)

and extract_rel_pure (pf : formula) (rel_name : spec_var): formula * (p_formula list)  =
  let pr_out = pr_pair !print_formula (pr_list !print_p_formula) in
  Debug.no_2 "extract_rel_pure" !print_formula !print_sv pr_out
    extract_rel_pure_x pf rel_name

(* Extract cylcic(B) from pf *)
and extract_cyclic_rel_pure_x (pf : formula) : formula * (p_formula list)  =
  let rel_sv = mk_spec_var Globals.cyclic_name in
  extract_rel_pure pf rel_sv

and extract_cyclic_rel_pure (pf : formula) : formula * (p_formula list)  =
  let pr_out = pr_pair !print_formula (pr_list !print_p_formula) in
  Debug.no_1 "extract_cyclic_rel_pure" !print_formula pr_out
    extract_cyclic_rel_pure_x pf

and extract_waitS_rel_pure (pf : formula) : formula * (p_formula list)  =
  let rel_sv = mk_spec_var Globals.waitS_name in
  extract_rel_pure pf rel_sv

and extract_concrete_rel_pure (pf : formula) : formula * (p_formula list)  =
  let rel_sv = mk_spec_var Globals.concrete_name in
  extract_rel_pure pf rel_sv


(*
  Check whether relation cylcic(B) is concrete:
  - B is a bag constraints
  - B is concrete in pf
*)
and check_concrete_cyclic_rel_pure_x (pf : formula) (rels: p_formula list) : bool  =
  let concrete_bags = get_concrete_bag_pure pf in
  let concrete_vars, _ = List.split concrete_bags in
  let check_concrete_one_rel rel =
    let str = !print_p_formula rel in
    match rel with
    | RelForm (sv,exps,pos) ->
      if (List.length exps !=1) then
        report_error no_pos ("extract_cyclic_rel_pure: expect a single arg in " ^ str ^ " ! \n")
      else
        let e = List.hd exps in
        (match e with
         | Var (sv,_) ->
           if (is_bag_tup2_typ sv) then
             let vars = find_closure_pure_formula sv pf in
             let res = Gen.BList.intersect_eq eq_spec_var vars concrete_vars in
             (res!=[])
           else report_error no_pos ("extract_cyclic_rel_pure: expect v of typ Tup2 in " ^ str ^ " !\n")
         | Bag _ -> true (*concrete bag*) 
         | _ -> report_error no_pos ("extract_cyclic_rel_pure: expect cyclic(v)! \n"))
    | _ -> report_error no_pos ("extract_cyclic_rel_pure: expecting RelForm! \n")
  in
  (*variables to check for concreteness*)
  let res = and_list (List.map check_concrete_one_rel rels) in
  res

and check_concrete_cyclic_rel_pure (pf : formula) (rels: p_formula list) : bool  =
  let pr1 = pr_list !print_p_formula in
  Debug.no_2 "check_concrete_cyclic_rel_pure" !print_formula pr1 string_of_bool
    check_concrete_cyclic_rel_pure_x pf rels

(* Check whether there is cyclic(B) *)
and has_cyclic_rel_pure_x f0 =
  let f_bf bf = 
    let pf,_ = bf in
    (match pf with
     | RelForm (SpecVar (_,id,_),_,pos) ->
       if (id = Globals.cyclic_name) then Some true
       else None
     | _ -> None)
  in
  fold_formula f0 (nonef, f_bf, nonef) or_list

and has_cyclic_rel_pure f0 =
  Debug.no_1 "has_cyclic_rel_pure" !print_formula string_of_bool
    has_cyclic_rel_pure_x f0

(* Check whether there is acyclic(B) *)
and has_acyclic_rel_pure_x f0 =
  let f_bf bf = 
    let pf,_ = bf in
    (match pf with
     | RelForm (SpecVar (_,id,_),_,pos) ->
       if (id = Globals.acyclic_name) then Some true
       else None
     | _ -> None)
  in
  fold_formula f0 (nonef, f_bf, nonef) or_list

and has_acyclic_rel_pure f0 =
  Debug.no_1 "has_acyclic_rel_pure" !print_formula string_of_bool
    has_acyclic_rel_pure_x f0

and has_waitS_rel_pure_x f0 =
  let f_bf bf = 
    let pf,_ = bf in
    (match pf with
     | RelForm (SpecVar (_,id,_),_,pos) ->
       if (id = Globals.waitS_name) then Some true
       else None
     | _ -> None)
  in
  fold_formula f0 (nonef, f_bf, nonef) or_list

(* Whether fo includes a relation waitS(...) *)
and has_waitS_rel_pure f0 =
  Debug.no_1 "has_waitS_rel_pure" !print_formula string_of_bool
    has_waitS_rel_pure_x f0

and has_rel_pure_x_with_name_x f0 name=
  let f_bf bf = 
    let pf,_ = bf in
    (match pf with
     | RelForm (SpecVar (_,id,_),_,pos) ->
       if (id = name) then Some true
       else None
     | _ -> None)
  in
  fold_formula f0 (nonef, f_bf, nonef) or_list

and has_rel_pure_x_with_name f0 name =
  Debug.no_2 "has_rel_pure_x_with_name" !print_formula (fun x -> x) string_of_bool
    has_rel_pure_x_with_name_x f0 name


and has_concrete_rel_pure_x f0 =
  has_rel_pure_x_with_name f0 Globals.concrete_name
  (* let f_bf bf =  *)
  (*   let pf,_ = bf in *)
  (*   (match pf with *)
  (*    | RelForm (SpecVar (_,id,_),_,pos) -> *)
  (*      if (id = Globals.concrete_name) then Some true *)
  (*      else None *)
  (*    | _ -> None) *)
  (* in *)
  (* fold_formula f0 (nonef, f_bf, nonef) or_list *)

(* Whether fo includes a relation concrete(S)*)
and has_concrete_rel_pure f0 =
  Debug.no_1 "has_concrete_rel_pure" !print_formula string_of_bool
    has_concrete_rel_pure_x f0

and has_univ_rel_pure_x f0 =
  has_rel_pure_x_with_name f0 "Univ"

and has_univ_rel_pure f0 =
  Debug.no_1 "has_univ_rel_pure" !print_formula string_of_bool
    has_univ_rel_pure_x f0



(*
  Expect: waitS(G,S,d)
  - rel is a RelForm
  - #exps = 3
  - G is of typ Tup2
  - S is concrete (i.e. it or its closure is in the concrete_bags)
  (sv closure is found in f)
  - G = {tup2(c,d) | c in S}

  Out: the formula forall (v1,v2) \in B. v1<v2
*)
and create_waitS_rel_x (concrete_bags:(spec_var * exp list) list) (f:formula) (rel : p_formula) : formula =
  let str = !print_p_formula rel in
  (match rel with
   | RelForm (sv,exps,pos) ->
     if (List.length exps !=3) then
       report_error no_pos ("create_waitS_rel: expect three args in " ^ str ^ " ! \n")
     else
       let g = List.hd exps in
       let s = List.hd (List.tl exps) in
       let d = List.hd (List.tl (List.tl exps)) in
       (match s with
        | Var (sv,_) ->
          (*Find all variable equal to sv*)
          let vars = find_closure_pure_formula sv f in
          if (is_bag_typ sv) then
            (try
               let _, exps = (List.find (fun (v1,_) -> Gen.BList.mem_eq eq_spec_var v1 vars) concrete_bags) in
               (*consistent*)
               let tups = List.fold_left (fun res e ->
                   let tup = Tup2 ((e,d),no_pos) in
                   tup::res) [] exps
               in
               let comprehension = Bag (tups, no_pos) in
               mkEqExp g comprehension no_pos
             with Not_found ->
               (*If the concrete bags cannot be found, keep the relation *)
               (* let () = print_endline ("[Warning] create_waitS_rel: expecting " ^ (!print_exp s)^" to be concrete!") in *)
               BForm ((rel, None) , None)
            )
          else
            report_error no_pos ("create_waitS_rel: expect v of typ Bag in " ^ str ^ " !\n")
        | _ -> report_error no_pos ("create_waitS_rel: expect waitS(G,S,d)! \n"))
   | _ -> report_error no_pos ("create_waitS_rel: expecting RelForm! \n"))

and create_waitS_rel (concrete_bags:(spec_var * exp list) list) (f:formula) (rel : p_formula) : formula =
  let pr1 = pr_list (pr_pair !print_sv (pr_list !print_exp)) in
  Debug.no_3 "create_waitS_rel"
    pr1
    !print_formula
    !print_p_formula
    !print_formula
    create_waitS_rel_x concrete_bags f rel

(*
  Expect: acylic(B)
  - rel is a RelForm
  - #exps = 1
  - sv is of typ Tup2
  - sv is concrete (i.e. it or its closure is in the concrete_bags)
  (sv closure is found in f)

  Out: the formula forall (v1,v2) \in B. v1<v2
*)
and create_acyclic_rel_x (concrete_bags:(spec_var * exp list) list) (f:formula) (rel : p_formula)  : formula =
  let str = !print_p_formula rel in
  (match rel with
   | RelForm (sv,exps,pos) ->
     if (List.length exps !=1) then
       report_error no_pos ("create_acyclic_rel: expect a single arg in " ^ str ^ " ! \n")
     else
       let e = List.hd exps in
       (match e with
        | Var (sv,_) ->
          (*Find all variable equal to sv*)
          let vars = find_closure_pure_formula sv f in
          if (is_bag_tup2_typ sv) then
            (try
               let _, exps = (List.find (fun (v1,_) -> Gen.BList.mem_eq eq_spec_var v1 vars) concrete_bags) in
               (*consistent*)
               List.fold_left (fun res e ->
                   match e with
                   | Tup2 ((e1,e2),_) ->
                     let lt_f = mkLtExp e1 e2 no_pos in
                     mkAnd res lt_f no_pos
                   | _ -> report_error no_pos ("create_acyclic_rel: expect Tup2 only !\n")
                 ) (mkTrue no_pos) exps
             with Not_found ->
               (*If the concrete bags cannot be found, keep the relation *)
               BForm ((rel, None) , None)
               (* report_error no_pos ("create_acyclic_rel: expect concrete " ^ (!print_sv sv) ^ " !\n") *)
            )
          else
            report_error no_pos ("create_acyclic_rel: expect v of typ Tup2 in " ^ str ^ " !\n")
        | _ -> report_error no_pos ("create_acyclic_rel: expect acyclic(v)! \n"))
   | _ -> report_error no_pos ("create_acyclic_rel: expecting RelForm! \n"))

and create_acyclic_rel (concrete_bags:(spec_var * exp list) list) (f:formula) (rel : p_formula) : formula =
  let pr1 = pr_list (pr_pair !print_sv (pr_list !print_exp)) in
  Debug.no_3 "create_acyclic_rel"
    pr1
    !print_formula
    !print_p_formula
    !print_formula
    create_acyclic_rel_x concrete_bags f rel


(*
  forall acyclic(B) in f.
  (1) B is a set of pairs. Otherwise, undefined (error)
  (2) B is concrete. Otherwise, undefined
  then, forall (v1,v2) \in B. v1<v2

  TODO: if B is partially concrete -> check its concrete part.
*)
and translate_acyclic_pure_x (f: formula) : formula =
  (*could be redundant but more complete*)
  let f = concretize_bag_pure f in
  (*attempt to concretize bag constraints*)
  let concrete_bags = get_concrete_bag_pure f in
  (*extract acyclic relations, and translate them*)
  let rel_sv = mk_spec_var Globals.acyclic_name in
  let (nf,rels) = extract_rel_pure f rel_sv in
  let fs = List.map (create_acyclic_rel concrete_bags nf) rels in
  let nf = List.fold_left (fun res f1 -> mkAnd res f1 no_pos) nf fs in
  nf

and translate_acyclic_pure (f: formula) : formula =
  Debug.no_1 "translate_acyclic_pure" !print_formula !print_formula
    translate_acyclic_pure_x f

and translate_waitS_pure_x (f: formula) : formula =
  (*could be redundant but more complete*)
  let f = concretize_bag_pure f in
  (*attempt to concretize bag constraints*)
  let concrete_bags = get_concrete_bag_pure f in
  (*extract waitS relations, and translate them*)
  let rel_sv = mk_spec_var Globals.waitS_name in
  let (nf,rels) = extract_rel_pure f rel_sv in
  let fs = List.map (create_waitS_rel concrete_bags nf) rels in
  let nf = List.fold_left (fun res f1 -> mkAnd res f1 no_pos) nf fs in
  nf

and translate_waitS_pure (f: formula) : formula =
  Debug.no_1 "translate_waitS_pure" !print_formula !print_formula
    translate_waitS_pure_x f

and translate_set_comp_pure_x (f: formula) : formula =
  (*could be redundant but more complete*)
  let f = concretize_bag_pure f in
  (*attempt to concretize bag constraints*)
  let concrete_bags = get_concrete_bag_pure f in
  (*extract waitS relations, and translate them*)
  let rel_sv = mk_spec_var Globals.set_comp_name in
  let (nf,rels) = extract_rel_pure f rel_sv in
  let fs = List.map (create_waitS_rel concrete_bags nf) rels in
  let nf = List.fold_left (fun res f1 -> mkAnd res f1 no_pos) nf fs in
  nf

and translate_set_comp_pure (f: formula) : formula =
  Debug.no_1 "translate_set_comp_pure" !print_formula !print_formula
    translate_set_comp_pure_x f

and find_closure_x (v:spec_var) (vv:(spec_var * spec_var) list) : spec_var list = 
  let rec helper (vs: spec_var list) (vv:(spec_var * spec_var) list) =
    match vv with
    | (v1,v2)::xs -> 
      let v3 = if (List.exists (fun v -> eq_spec_var v v1) vs) then Some v2
        else if (List.exists (fun v -> eq_spec_var v v2) vs) then Some v1
        else 
          None 
      in
      (match v3 with
       | None -> helper vs xs
       | Some x -> helper (x::vs) xs)
    | [] -> vs
  in
  (*let vs = [v] in*)
  let rec helper_loop vs vv =
    let vs_new = helper vs vv in
    if (Gen.BList.difference_eq eq_spec_var vs_new vs) =[] then
      vs (* Reach a fixpoint*)
    else
      (*if found new vars --> iterate*)
      helper_loop vs_new vv
  in
  helper_loop [v] vv

and find_closure (v:spec_var) (vv:(spec_var * spec_var) list) : spec_var list = 
  Debug.no_2 "find_closure" 
    !print_sv
    (pr_list (pr_pair !print_sv !print_sv))
    !print_svl
    find_closure_x v vv

and find_all_closures_x (vv: (spec_var * spec_var) list) : (spec_var list) list = 
  match vv with
  | [] -> []
  | (v1, v2)::vs ->
    let v1_closure = find_closure v1 vv in
    let rem_vs = List.filter (fun (v3, v4) ->
      not (Gen.BList.mem_eq eq_spec_var v3 v1_closure) &&
      not (Gen.BList.mem_eq eq_spec_var v4 v1_closure)) vs in
    v1_closure::(find_all_closures_x rem_vs)

and find_all_closures (vv: (spec_var * spec_var) list) : (spec_var list) list = 
  Debug.no_1 "find_all_closures" (pr_list (pr_pair !print_sv !print_sv)) (pr_list !print_svl)
    find_all_closures_x vv

and find_closure_pure_formula_x (v:spec_var) (f:formula) : spec_var list = 
  find_closure v (pure_ptr_equations f)

and find_closure_pure_formula (v:spec_var) (f:formula) : spec_var list = 
  Debug.no_2 "find_closure_pure_formula" 
    !print_sv
    !print_formula
    !print_svl
    find_closure_pure_formula_x v f

(*s2*)
let prune_irr_neq_b_form b irr_svl =
  let (pf,c) = b in
  match pf with
  | Neq (a1, a2, pos)
  (* | Eq (a1, a2, pos) *) -> begin
      match a1,a2 with
      | Var (sv1,pos1), Var (sv2,pos2) ->
        if (List.exists (fun sv -> (eq_spec_var sv sv1) || (eq_spec_var sv sv2)) irr_svl) then
          (true,  (BConst (true,pos),c))
        else (false,b)
      | Var (sv,pos), Null _
      | Null _, Var (sv,pos) ->
        if (List.exists (fun sv1 -> (eq_spec_var sv sv1)) irr_svl) then
          (true,  (BConst (true,pos),c))
        else (false,b)
      | _ -> (false,b)
    end
  | _ -> (false,b)

let prune_irr_neq_b_form b irr_svl =
  let pr = !print_b_formula in
  let prr = pr_pair string_of_bool pr in
  Debug.no_2 "prune_irr_neq_b_form" pr !print_svl prr
    prune_irr_neq_b_form b irr_svl

let prune_irr_neq p0 irr_svl =
  let aliases = pure_ptr_equations_aux false p0 in
  let alias_lst = find_all_closures aliases in
  let irr_svl = List.filter (fun sv ->
    try
      let sv_alias = List.find (fun alias -> Gen.BList.mem_eq eq_spec_var sv alias) alias_lst in
      Gen.BList.subset_eq eq_spec_var sv_alias irr_svl
    with _ -> true) irr_svl in
  let rec helper p =
    match p with
    | BForm (bf,a) -> let b,nbf = prune_irr_neq_b_form bf irr_svl in
      if b then b, mkTrue no_pos else
        false, BForm (nbf,a)
    | And (p1,p2,pos) -> begin
        let b1,np1 = (helper p1) in
        let b2,np2 = (helper p2) in
        match b1,b2 with
        | true,true -> (true, mkTrue no_pos)
        | true,false -> false,np2
        | _, true -> false,np1
        | _ -> (false,mkAnd np1 np2 pos)
      end
    | AndList b-> false,p (* let ls_and,svl = List.fold_left (fun (ls1,) (sl,b1) -> *)
    (*     let nb1,svl1 = helper b1 in *)
    (*     if svl1 = [] then ls1@[(sl,b1)],svl0 else *)
    (*       ls1,svl0@svl1 *)
    (* ) ([],[]) b in *)
    (* if svl = [] then (mkTrue no_pos, []) else *)
    (*   AndList ls_and,svl *)
    | Or (b1,b2,_,_) -> (*intersect_svl (helper b1) (helper b2)*)
      false,p
    | Not (b, _,pos) -> let b,np = helper b in
      if b then false,mkFalse no_pos else (false, np)
    | Forall (a,b,c,pos)-> let b,np = helper b in
      if b then b,mkTrue pos else false,Forall (a,np,c,pos)
    | Exists (q,b,lbl,pos)-> let b,np = helper b in
      if b then b,mkTrue pos else (false,Exists (q,np,lbl,pos))
  in
  helper p0

let prune_irr_neq p0 svl=
  let irr_svl = diff_svl (remove_dups_svl (fv p0)) svl in
  let pr1= !print_formula in
  let pr2 = !print_svl in
  Debug.no_2 "prune_irr_neq" pr1 pr2 (pr_pair string_of_bool pr1)
    (fun _ _ -> prune_irr_neq p0 irr_svl ) p0 irr_svl

let is_irr_eq_b_form b svl=
  let (pf,c) = b in
  match pf with
  | Eq (a1, a2, pos) -> begin
      match a1,a2 with
      | Var (sv1,pos1), Var (sv2,pos2) ->
        not (mem_svl sv1 svl && mem_svl sv2 svl)
      | _ -> false
    end
  | _ -> false

let is_irr_eq_x p0 svl=
  let rec helper p=
    match p with
    | BForm (bf,a) -> is_irr_eq_b_form bf svl
    | _ -> false
  in
  helper p0

let is_irr_eq p0 svl=
  let pr1= !print_formula in
  let pr2 = !print_svl in
  Debug.no_2 "is_irr_eq" pr1 pr2 string_of_bool
    (fun _ _ -> is_irr_eq_x p0 svl ) p0 svl

let prune_irr_eq p svl=
  let ps = split_conjunctions p in
  let ps1 = List.filter (fun p -> not (is_irr_eq p svl)) ps in
  conj_of_list ps1 (pos_of_formula p)

let get_null_ptrs_p pf=
  match pf with
  | Eq (e1, e2, _) -> if is_null e1 then (afv e2)
    else if is_null e2 then (afv e1)
    else []
  | _ -> []

let get_null_ptrs p0 =
  let rec helper p=
    match p with
    | BForm ((pf,_),_) -> let svl = get_null_ptrs_p pf in svl
    | And (p1,p2,_) ->
      (helper p1)@(helper p2)
    | AndList b-> List.fold_left (fun ls (_, p1) -> ls@(helper p1)) [] b
    | Or (b1,b2,_,_) -> (helper b1)@(helper b2)
    | Not (b, _,pos) -> []
    | Forall (a,b,c,pos)-> let svl = helper b in (diff_svl svl [a])
    | Exists (q,b,lbl,pos)-> let svl = helper b in (diff_svl svl [q])
  in
  remove_dups_svl (helper p0)


let checkeq_exp e1 e2 ss=
  match e1,e2 with
  | Var (sv1,_), Var (sv2,_) ->
    let nsv1 = subs_one ss sv1 in
    if eq_spec_var nsv1 sv2 then (true) else false
  | _ -> (false)

let checkeq_p p1 p2 ss=
  match p1,p2 with
  | Lte (e11,e12,_),  Lte (e21,e22,_) -> begin
      if checkeq_exp e11 e21 ss then
        match e12,e22 with
        | Var (sv1,_), Var (sv2,_) -> (true, ss@[(sv1,sv2)])
        | _ -> (false, ss)
      else
        (false, ss)
    end
  | Gte (e11,e12,_),  Gte (e21,e22,_) -> begin
      if checkeq_exp e11 e21 ss then
        match e12,e22 with
        | Var (sv1,_), Var (sv2,_) -> (true, ss@[(sv1,sv2)])
        | _ -> (false, ss)
      else
        (false, ss)
    end
  | Lte (e11,e12,_),  Gte (e22,e21,_) -> begin
      if checkeq_exp e11 e21 ss then
        match e12,e22 with
        | Var (sv1,_), Var (sv2,_) -> (true, ss@[(sv1,sv2)])
        | _ -> (false, ss)
      else
        (false, ss)
    end
  | Gte (e11,e12,_),  Lte (e22,e21,_) -> begin
      if checkeq_exp e11 e21 ss then
        match e12,e22 with
        | Var (sv1,_), Var (sv2,_) -> (true, ss@[(sv1,sv2)])
        | _ -> (false, ss)
      else
        (false, ss)
    end
  | _ -> (false, ss)

let checkeq_p p1 p2 ss=
  let pr1 = !print_p_formula in
  let pr3 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_3 "checkeq_p" pr1 pr1 pr3 (pr_pair string_of_bool pr3)
    (fun _ _ _ -> checkeq_p p1 p2 ss)
    p1 p2 ss


let checkeq_x p1 p2 ss=
  match p1, p2 with
  | (BForm ((pf1,_),_)), (BForm ((pf2,_),_)) ->
    checkeq_p pf1 pf2 ss
  | _ -> (false, ss)

let checkeq p1 p2 ss=
  let pr1 = !print_formula in
  let pr3 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_3 "checkeq" pr1 pr1 pr3 (pr_pair string_of_bool pr3)
    (fun _ _ _ -> checkeq_x p1 p2 ss)
    p1 p2 ss


let get_cmp_form_exp e1 e2=
  match e1,e2 with
  | Var (sv1,_), Var (sv2,_) ->
    [(sv1,sv2)]
  | _ -> []

let get_cmp_form_p p=
  match p with
  (* | Eq (e1,e2,_) *)
  (* | Neq (e1,e2,_) *)
  | Lte (e1,e2,_)
  | Gte (e1,e2,_)
  | Gt (e1,e2,_)
  | Lt (e1,e2,_) -> get_cmp_form_exp e1 e2
  | _ -> []

let get_cmp_form_x p0=
  let rec helper p=
    match p with
    | (BForm ((pf,_),_)) ->
      get_cmp_form_p pf
    | And (p1,p2, _) -> (helper p1)@(helper p2)
    | AndList lp -> List.fold_left (fun r (_,p) -> r@(helper p)) [] lp
    | Or (p1 , p2 , _, _) -> (helper p1)@(helper p2)
    | Not (p,_ , _) -> helper p
    | Forall (_ , p,_,_) -> helper p
    | Exists (_, p,_,_) -> helper p
  in
  helper p0


(*x>y; x>= y; x<t; x<=y, x=y*)
let get_cmp_form p =
  let pr1 = !print_formula in
  let pr3 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_1 "get_cmp_form" pr1 pr3
    (fun _ -> get_cmp_form_x p) p

let is_cmp_form_p p=
  match p with
  | Eq (e1,e2,_)
  | Neq (e1,e2,_)
  | Lte (e1,e2,_)
  | Gte (e1,e2,_)
  | Gt (e1,e2,_)
  | Lt (e1,e2,_) -> (get_cmp_form_exp e1 e2) != []
  | _ -> false

let is_cmp_form p =
  match p with
  | (BForm ((pf,_),_)) -> is_cmp_form_p pf
  | _ -> false

let rhs_needs_or_split f = 	match f with
  | Or _ -> not(no_andl f)
  | _-> false

let count_disj f =
  let k = split_disjunctions f
  in List.length k


let mkAndList_opt f =
  (* let f = mkAndList f in *)
  if !Globals.remove_label_flag then
    join_conjunctions (List.map snd f)
  else mkAndList f

let extract_eq_clauses_formula f =
  let lst = split_conjunctions f in
  List.filter is_eq_between_no_bag_vars lst

let extract_eq_clauses_lbl_lst lst =
  let rec aux conjs lst =
    match lst with
    | []   -> (conjs, [])
    | (lbl,f)::t ->
      let eq_f_lst = extract_eq_clauses_formula f in
      let (all_eq, tail) = aux (conjs@eq_f_lst) t in
      let eqs_to_add = Gen.BList.difference_eq (equalFormula) all_eq eq_f_lst in
      let conj = join_conjunctions eqs_to_add in
      let new_f = mkAnd f conj no_pos in
      (all_eq, (lbl,new_f)::tail)
  in
  snd (aux [] lst)

let extract_eq_clauses_lbl_lst lst =
  let pr = pr_list (pr_pair pr_none !print_formula) in
  Debug.no_1 "extract_eq_clauses_lbl_lst"  pr pr  extract_eq_clauses_lbl_lst lst

let is_ieq f =
  match f with
  | BForm (b,_) ->
    let pf,_ = b in
    begin
      match pf with
      | Neq _ | Gt _ | Gte _
      | Lt _ | Lte _ -> true
      |_ -> false
    end
  | _ -> false

(* let swap_null_x (f : formula) : formula = *)
(*   let f_e e = Some e in *)
(*   let f_b ((pf,ann) as bf) = *)
(*     match pf with *)
(*       | Eq (e1, e2, l) -> begin *)
(*           match e1 with *)
(*             | Null _ -> Some ((Eq (e2, e1, l)), ann) *)
(*             | _ -> Some bf *)
(*         end *)
(*       | _ -> Some bf *)
(*   in *)
(*   transform_formula ((fun _-> None),(fun _-> None), (fun _-> None),f_b,f_e) f *)

(* let swap_null (f : formula) : formula = *)
(*   let pr1 = !print_formula in *)
(*   Debug.no_1 "CP.swap_null" pr1 pr1 *)
(*       (fun _ -> swap_null_x f) f *)



(*used in the optimization that in between hoare rules dead variables should be quantified*)

let eq_pair_eq (a1,a2) (b1,b2) = ((eq_spec_var a1 b1) &&  (eq_spec_var a2 b2)) || ((eq_spec_var a1 b2) &&  (eq_spec_var a2 b1))

let drop_dupl_x f = 
  let rec helper f = 
    let rec splitter (a,o) f = match f with
      | BForm _ -> f::a,o
      | And (f1,f2,_) -> splitter (splitter (a,o) f1) f2 
      | AndList l -> a, (AndList (map_l_snd helper l))::o
      | Or _ 
      | Not _ 
      | Forall _ 
      | Exists _ -> a, f::o in
    let a,o = splitter ([],[]) f in		
    join_conjunctions ((remove_dupl_conj_list a)@o)	in
  join_disjunctions (List.map helper (split_disjunctions f)) 

let drop_dupl f = 
  Debug.no_1 "drop_dupl" !print_formula !print_formula drop_dupl_x f

let drop_triv_eq f =
  let fc f = match f with
    | BForm ((Eq(Var(vl,_),Var(vr,_),l),_),_) -> 
      if eq_spec_var vl vr then Some (mkTrue l)
      else Some f
    | BForm _ -> Some f
    | _ -> None in
  drop_dupl(transform_formula (nonef, nonef,fc,somef,somef) f)


(*returns a list of substitutions that can be safely applied over the entire formula*)
let get_vv_eqs (f0 : formula) : (spec_var * spec_var) list =
  let fct p f = match f with 
    | BForm ((Eq (Var(vl,_),Var(vr,_),_),_),_) ->  if p then Some (f,[(vl,vr)]) else Some (f,[])
    | BForm ((Neq(Var(vl,_),Var(vr,_),_),_),_) ->  if p then Some (f,[]) else Some (f,[(vl,vr)])
    | BForm _ -> Some (f,[])
    | _ -> None in
  let f_arg arg e = match e with | Not _ -> not arg | _ -> arg in
  let f_cmb e l = match e with 
    | BForm _  | And _ | AndList _  | Not _ -> List.concat l
    | Or _ -> Gen.BList.intersect_eq eq_pair_eq  (List.hd l) (List.hd (List.tl l)) 
    | Forall (sv,_,_,_) 
    | Exists (sv,_,_,_) -> List.filter (fun (v1,v2)-> not ((eq_spec_var sv v1)||(eq_spec_var sv v2)))(List.concat l) in 
  let f_stop1 a b = Some (b,[]) in
  let f_stop2 a b = Some (b,[]) in
  snd (foldr_formula f0 true (fct,f_stop1, f_stop2) (f_arg,idf2,idf2) (f_cmb, (fun _ _ -> []), (fun _ _ -> [])))

let get_neqs (f0 : formula) : ((spec_var * spec_var) list) * (spec_var list) =
  let fct p f = match f with 
    | BForm ((Eq (Var(vl,_),Var(vr,_),_),_),_) ->  if p then Some (f,([],[])) else Some (f,([(vl,vr)],[]))
    | BForm ((Neq(Var(vl,_),Var(vr,_),_),_),_) ->  if p then Some (f,([(vl,vr)],[])) else Some (f,([],[])) 
    | BForm ((Eq (Null _ ,Var(v ,_),_),_),_)
    | BForm ((Eq (Var(v ,_),Null _ ,_),_),_) ->  if p then Some (f,([],[])) else Some (f,([],[v]))
    | BForm ((Neq(Var(v ,_),Null _ ,_),_),_)
    | BForm ((Neq(Null _ ,Var(v ,_),_),_),_) -> if p then Some (f,([],[v])) else Some (f,([],[])) 
    | BForm _ -> Some (f,([],[]))
    | _ -> None in
  let f_arg arg e = match e with | Not _ -> not arg | _ -> arg in
  let f_cmb e l :((spec_var * spec_var) list) * (spec_var list)  = match e with 
    | BForm _  | And _ | AndList _  | Not _ -> Gen.fold_pair2f List.concat List.concat (List.split l)
    | Or _ -> 
      let r1neq, r1null = List.hd l in
      let r2neq, r2null = List.hd (List.tl l) in
      Gen.BList.intersect_eq eq_pair_eq r1neq r2neq , r1null@r2null
    | Forall (sv,_,_,_) 
    | Exists (sv,_,_,_) -> 
      let l1,l2 = Gen.fold_pair2f List.concat List.concat (List.split l) in
      List.filter (fun (v1,v2)-> not ((eq_spec_var sv v1)||(eq_spec_var sv v2))) l1,
      List.filter (fun v-> not (eq_spec_var sv v)) l2 in 
  let f_stop1 a b = Some (b,([],[])) in
  let f_stop2 a b = Some (b,([],[])) in
  snd (foldr_formula f0 true (fct,f_stop1, f_stop2) (f_arg,idf2,idf2) (f_cmb, (fun _ _ -> ([],[])), (fun _ _ -> ([],[]))))

let drop_neq (aneq,anull) f = 
  let f_tr e = match e with
    | BForm ((Neq(Var(vl,_),Var(vr,_),l),_),_) -> 
      if List.exists (eq_pair_eq (vl,vr)) aneq then Some (mkTrue no_pos) else Some e
    | BForm ((Neq((Null _),Var(v,_),_),_),_)
    | BForm ((Neq(Var(v,_),(Null _),_),_),_) -> 
      if (List.exists (eq_spec_var v) anull) then Some (mkTrue no_pos) else Some e
    | Not _ -> Some e
    | BForm _ -> Some e 
    | _ -> None in
  transform_formula (somef,somef,f_tr,somef,somef) f


(*lump all pointer vars apearing in anything but disequalities*)
let force_all_vv_eqs_x f0 = 
  let rec helper b f = match f with
    | BForm ((Eq (Var(vl,_),Var(vr,_),_),_),_) ->  if b&&(not (eq_spec_var vl vr)) then [vl;vr] else []
    | BForm ((Eq(Var(vl,_),(Null _),_),_),_)
    | BForm ((Eq((Null _),Var(vl,_),_),_),_)->   if b then [vl] else []
    | BForm ((Neq(Var(vl,_),Var(vr,_),_),_),_) ->  if b&&(not (eq_spec_var vl vr)) then [] else [vl;vr]
    | BForm ((Neq(Var(vl,_),(Null _),_),_),_)
    | BForm ((Neq((Null _),Var(vl,_),_),_),_)->   if b then [] else [vl]
    | BForm (b,_) -> bfv b 
    | Or (f1,f2,_,_)
    | And (f1,f2,_)-> (helper b f1) @ (helper b f2)
    | AndList l -> Gen.fold_l_snd (helper b) l	
    | Not (f,_,_)-> helper (not b) f
    | Forall (_,f,_,_) 
    | Exists (_,f,_,_)-> helper b f  in
  remove_dups_svl (List.filter is_node_typ (helper true f0))

let force_all_vv_eqs f0 =
  Debug.no_1 "force_all_vv_eqs" !print_formula !print_svl force_all_vv_eqs_x f0

(*the next set of functions deal with elimination of equalities and disequalities, and early detection of contradictions*)
(*mainly due to the performance penalty of disequalities *)

let decide_keep vars_to_keep v = 
  (not (is_node_typ v)) || (List.exists (eq_spec_var v) vars_to_keep)

(*get ante substitutions and try and apply as many as possible*)
let expand_eqs_x ante conseq = 
  let a_alias = get_vv_eqs ante in
  let rec sub (ante,conseq) nf = match nf with 
    | [] -> (ante,conseq)
    | h::t -> 
      let t = List.map (fun (c1,c2)-> subst_var h c1, subst_var h c2) t in
      sub (subst [h] ante ,subst [h] conseq) t in
  sub (ante,conseq) a_alias

let expand_eqs ante conseq = 
  let pr = !print_formula in
  Debug.no_2 "expand_eqs" pr pr (pr_pair pr pr) expand_eqs_x ante conseq

let check_pointer_dis_sat_x c = 
  let helper nf = 
    let nf ,_= expand_eqs nf (mkTrue no_pos) in
    let vars_to_keep = force_all_vv_eqs nf in
    let f a c = match c with 
      | BForm ((Neq(Var(vl,_),Var(vr,_),l),_),_) -> 
        if eq_spec_var vl vr then Some (c, false)
        else if (decide_keep vars_to_keep vl)&& (decide_keep vars_to_keep vr) then Some (c,a)
        else Some (mkTrue no_pos, a)
      | BForm ((Eq(Var(vl,_),Var(vr,_),l),_),_) -> 
        if eq_spec_var vl vr then Some (mkTrue no_pos, a)
        else Some (c,a)
      | BForm ((Neq((Null _),Var(v,_),_),_),_)
      | BForm ((Neq(Var(v,_),(Null _),_),_),_) -> 
        if (decide_keep vars_to_keep v) then Some (c,a) else Some (mkTrue no_pos, a)
      | BForm _ -> Some (c,a)
      | _ -> None  in
    let f_comb = 
      (fun f l -> (match f with Or _ -> or_list l | _ -> and_list l)),
      (fun _ l -> and_list l),
      (fun _ l -> and_list l) in
    foldr_formula nf true (f, (fun a c-> Some (c,a)), (fun a c-> Some (c,a))) (idf2,idf2,idf2) f_comb in
  List.fold_left (fun (a1,a2) c-> 
      let r1,r2 = helper c in
      mkOr a1 (drop_dupl r1) None no_pos , (a2||r2) ) (mkFalse no_pos, false) (split_disjunctions c)  


(*not equivalence preserving, use carefully, designed as a simplification pre unsat check*)
let check_pointer_dis_sat c= 
  Debug.no_1 "check_pointer_dis_sat" !print_formula (pr_pair !print_formula string_of_bool) check_pointer_dis_sat_x c

let simpl_equalities_x ante conseq = 
  let ante, conseq = expand_eqs ante conseq in
  let a_neq = get_neqs ante in
  let conseq = drop_neq a_neq conseq in
  let vars_to_keep = (force_all_vv_eqs ante)@(fv conseq) in
  let f e = match e with
    | BForm ((Neq(Var(vl,_),Var(vr,_),l),_),_) -> 
      if eq_spec_var vl vr then Some (mkFalse no_pos)
      else if (decide_keep vars_to_keep vl)&& (decide_keep vars_to_keep vr) then Some e
      else Some (mkTrue no_pos)
    | BForm ((Eq(Var(vl,_),Var(vr,_),l),_),_) -> 
      if eq_spec_var vl vr then Some (mkTrue no_pos)
      else Some e
    | BForm ((Neq((Null _),Var(v,_),_),_),_)
    | BForm ((Neq(Var(v,_),(Null _),_),_),_) -> 
      if (decide_keep vars_to_keep v) then Some e else Some (mkTrue no_pos)
    | BForm _ -> Some e 
    | _ -> None in
  let tr = transform_formula (somef,somef,f,somef,somef) in
  drop_dupl (tr ante), tr conseq

(*a simplification pre imply check*)
let simpl_equalities ante conseq  = 
  let pr = !print_formula in
  Debug.no_2 "simpl_equalities" pr pr (pr_pair pr pr) simpl_equalities_x ante conseq

(* For template *)
(* Return transformed formula and list of templates, which need to be inferred *)
let trans_formula_templ (i_templ_ids: spec_var list) (f: formula): formula * spec_var list =
  let f_arg arg _ = arg in 
  let f_e _ e = match e with
    | Template t ->
      if t.templ_unks = [] then 
        match t.templ_body with
        | None -> Some (mkIConst 0 t.templ_pos, ([], true))
        | Some b -> Some (b, ([], false))
      else if mem_svl t.templ_id i_templ_ids then
        let templ_unks = List.concat (List.map afv t.templ_unks) in
        Some (exp_of_template t, (templ_unks, false))
      else Some (mkIConst 0 t.templ_pos, ([], true))
    | _ -> None
  in
  let f_comb c = 
    let vl, is_only_zero = List.split c in
    (List.concat vl, 
     is_only_zero != [] && (List.for_all (fun i -> i) is_only_zero))
  in
  let f_b _ b = 
    let nb, (templ_unks, is_only_zero) = trans_b_formula b () 
        (nonef2, f_e) (f_arg, f_arg) f_comb in
    if is_only_zero then Some (mkTrue_b (pos_of_b_formula b), ([], false))
    else Some (nb, (templ_unks, false))
  in
  let nf, (templ_unks, _) = trans_formula f ()
      (nonef2, f_b, f_e) (f_arg, f_arg, f_arg) f_comb
  in (nf, templ_unks)

let trans_formula_templ (i_templ_ids: spec_var list) (f: formula): formula * spec_var list =
  let pr1 = !print_svl in
  let pr2 = !print_formula in
  Debug.no_2 "trans_formula_templ" pr1 pr2 (pr_pair pr2 pr1)
             trans_formula_templ i_templ_ids f

let collect_templ_var f =
  let f_e e =
    match e with
    | Template t ->
       Some [t.templ_id]
    | _ -> None
  in
  fold_formula f (nonef,nonef,f_e) List.concat
;;
             


(* imm utilities *)
let rec fv_ann (a: ann) = match a with
  | ConstAnn _ | NoAnn -> []
  | TempAnn v  -> fv_ann v
  | TempRes(v,w) -> (fv_ann w)@(fv_ann v)
  | PolyAnn v  -> [v]

let rec fv_ann_lst (a:ann list) = match a with
  | [] -> []
  | h :: t -> (fv_ann h) @ (fv_ann_lst t)

let mkConstAnn ann = ConstAnn ann

(* match i with  *)
(*   | 0 -> ConstAnn Mutable *)
(*   | 1 -> ConstAnn Imm *)
(*   | 2 -> ConstAnn Lend *)
(*   | 3 -> ConstAnn Accs *)
(*   | _ -> report_error no_pos "Const Ann must be less than 3"   *)

let mkPolyAnn v = PolyAnn v

let mkExpAnn ann pos =
  match ann with
  | TempAnn _ | NoAnn -> IConst(int_of_heap_ann Accs, pos)
  | TempRes (v,w) -> IConst(int_of_heap_ann Accs, pos)
  | ConstAnn a -> IConst(int_of_heap_ann a, pos)
  | PolyAnn v  -> Var(v, pos)

let mkExpAnnSymb ann pos =
  match ann with
  | TempAnn _ -> AConst(Accs, pos)
  | TempRes _ -> AConst(Accs, pos)
  | ConstAnn a -> AConst(a, pos)
  | PolyAnn v  -> Var(v, pos)
  | NoAnn  -> AConst(Accs, pos)

(* let int_imm_to_exp i loc =  *)
(*   mkExpAnnSymb (mkConstAnn (heap_ann_of_int i)) loc *)

(* let ann_sv_lst  = (name_for_imm_sv Mutable):: (name_for_imm_sv Imm):: (name_for_imm_sv Lend)::[(name_for_imm_sv Accs)] *)

(* let is_ann_const_sv sv =  *)
(*   match sv with *)
(*   | SpecVar(AnnT,a,_) -> List.exists (fun an -> an = a ) ann_sv_lst *)
(*   | _                 -> false *)

(* let helper_is_const_ann_sv em sv test = *)
(*   let imm_const_sv = mkAnnSVar test in *)
(*   if not (is_ann_typ sv) then false *)
(*   else if eq_spec_var sv imm_const_sv then true *)
(*   else EMapSV.is_equiv em sv imm_const_sv  *)

(* let is_mut_sv ?emap:(em=[])  sv = helper_is_const_ann_sv em sv Mutable  *)

(* let is_imm_sv ?emap:(em=[])  sv = helper_is_const_ann_sv em sv Imm *)

(* let is_lend_sv ?emap:(em=[]) sv = helper_is_const_ann_sv em sv Lend *)

(* let is_abs_sv ?emap:(em=[])  sv = helper_is_const_ann_sv em sv Accs *)

(* let is_imm_const_sv ?emap:(em=[])  sv =  *)
(*   (is_abs_sv ~emap:em sv) ||   (is_mut_sv ~emap:em sv) ||   (is_lend_sv ~emap:em sv) ||   (is_imm_sv ~emap:em sv) *)

(* let get_imm_list ?loc:(l=no_pos) list = *)
(*   let elem_const = (mkAnnSVar Mutable)::(mkAnnSVar Imm)::(mkAnnSVar Lend)::[(mkAnnSVar Accs)] in *)
(*   let anns_ann =  (ConstAnn(Mutable))::(ConstAnn(Imm))::(ConstAnn(Lend))::[(ConstAnn(Accs))] in *)
(*   let anns_exp =  (AConst(Mutable,l))::(AConst(Imm,l))::(AConst(Lend,l))::[(AConst(Accs,l))] in *)
(*   let anns = List.combine anns_ann anns_exp in *)
(*   let lst = List.combine elem_const anns in *)
(*   let imm =  *)
(*     try *)
(*       Some (snd (List.find (fun (a,_) -> EMapSV.mem a list  ) lst ) ) *)
(*     with Not_found -> None *)
(*   in imm *)

(* let get_imm_emap ?loc:(l=no_pos) sv emap = *)
(*   let aliases = EMapSV.find_equiv_all sv emap in *)
(*   get_imm_list ~loc:l aliases *)

(* let get_imm_emap_exp  ?loc:(l=no_pos) sv emap : exp option = map_opt snd (get_imm_emap ~loc:l sv emap) *)
(* let get_imm_emap_ann  ?loc:(l=no_pos) sv emap : ann option = map_opt fst (get_imm_emap ~loc:l sv emap) *)

(* let eq_const_ann const_imm em sv =  *)
(*   match const_imm with *)
(*   | Mutable -> is_mut_sv ~emap:em sv *)
(*   | Imm     -> is_imm_sv ~emap:em sv *)
(*   | Lend    -> is_lend_sv ~emap:em sv *)
(*   | Accs    -> is_abs_sv ~emap:em sv *)

(* let helper_is_const_imm em (imm:ann) const_imm =  *)
(*   match imm with *)
(*   | ConstAnn a -> a == const_imm *)
(*   | PolyAnn sv -> eq_const_ann const_imm em sv  *)
(*   | _ -> false *)

(* (\* below functions take into account the alias information while checking if imm is a certain const. *\) *)
(* let is_abs ?emap:(em=[]) (imm:ann) = helper_is_const_imm em imm Accs *)

(* let is_abs_list ?emap:(em=[]) imm_list = List.for_all (is_abs ~emap:em) imm_list *)

(* let is_mutable ?emap:(em=[]) (imm:ann) = helper_is_const_imm em imm Mutable  *)

(* let is_mutable_list ?emap:(em=[]) imm_list =  List.for_all (is_mutable ~emap:em) imm_list *)

(* let is_immutable ?emap:(em=[]) (imm:ann) = helper_is_const_imm em imm Imm *)

(* let is_immutable_list ?emap:(em=[]) imm_list =  List.for_all (is_immutable ~emap:em) imm_list *)

(* let is_lend ?emap:(em=[]) (imm:ann) = helper_is_const_imm em imm Lend *)

(* let is_lend_list ?emap:(em=[]) imm_list =  List.for_all (is_lend ~emap:em) imm_list *)

let isAccs (a : ann) : bool = 
  match a with
  | ConstAnn Accs -> true 
  | _ -> false

let isLend(a : ann) : bool = 
  match a with
  | ConstAnn Lend -> true 
  | _ -> false

let isMutable(a : ann) : bool = 
  match a with
  | ConstAnn Mutable -> true 
  | _ -> false

let isImm(a : ann) : bool = 
  match a with
  | ConstAnn Imm -> true 
  | _ -> false

let isPoly(a : ann) : bool =
  match a with
  | PolyAnn v -> true
  | _ -> false

let rec apply_one_imm_x (fr,t) a = match a with
  | ConstAnn _ | NoAnn -> a
  | TempAnn t1 -> TempAnn(apply_one_imm_x (fr,t) t1)
  | TempRes (tl,tr) ->  TempRes(apply_one_imm_x (fr,t) tl, apply_one_imm_x (fr,t) tr)
  | PolyAnn sv ->  PolyAnn (if eq_spec_var sv fr then t else sv)

let apply_one_imm (fr,t) a = 
  let pr1 =  (pr_pair !print_sv !print_sv) in
  let pr2 = string_of_imm in
  Debug.no_2 "apply_one_imm" pr1 pr2 pr2 apply_one_imm_x (fr,t) a

let rec subs_imm_par_x sst a = match a with
  | ConstAnn _ | NoAnn -> a
  | TempAnn t1 -> TempAnn(subs_imm_par_x sst t1)
  | TempRes (tl,tr) -> TempRes(subs_imm_par_x sst tl,subs_imm_par_x sst tr)
  | PolyAnn sv ->  (* CP.PolyAnn (CP.subst_var_par sst sv) *)
    PolyAnn (subs_one sst sv)

let subs_imm_par sst a = 
 let pr1 =  pr_list (pr_pair !print_sv !print_sv) in
 let pr2 = string_of_imm in
 Debug.no_2 "subs_imm_par" pr1 pr2 pr2 subs_imm_par_x sst a

(* let is_const_imm ?emap:(em=[]) (a:ann) : bool = *)
(*   match a with *)
(*   | ConstAnn _ -> true *)
(*   | PolyAnn sv -> (is_mutable ~emap:em a) || (is_immutable ~emap:em a) || (is_lend ~emap:em a) || (is_abs ~emap:em a) *)
(*   | _ -> false *)

(* let is_const_imm_list ?emap:(em=[]) (alst:ann list) : bool = *)
(*   List.for_all (is_const_imm ~emap:em) alst *)

(* end imm utilities *)


(* utilities for allowing annotations as view arguments *)
let eq_annot_arg a1 a2 =
  match a1,a2 with
  | ImmAnn a1, ImmAnn a2 -> eq_ann a1 a2

let eq_view_arg a1 a2 = 
  match a1, a2 with
  | SVArg sv1, SVArg sv2     -> eq_spec_var sv1 sv2
  | AnnotArg a1, AnnotArg a2 -> eq_annot_arg a1 a2
  | _ -> false

let mkSVArg sv = SVArg sv

let mkImmAnn a = ImmAnn a

let mkAnnotArg a = AnnotArg a

let is_view_var_arg (arg:view_arg): bool =
  match arg with
  | SVArg _ -> true
  | _       -> false

let is_view_annot_arg (arg:view_arg): bool =
  match arg with
  | AnnotArg _ -> true
  | _          -> false

let eq_annot_arg a1 a2 =
  match a1,a2 with
  | ImmAnn a1, ImmAnn a2 -> eq_ann a1 a2

let annot_arg_to_imm_ann (arg: annot_arg ): ann  =
  match arg with
  | ImmAnn a -> a
(* continue from here with other type of ann *)

let annot_arg_to_imm_ann_list (arg: annot_arg list): ann list =
  List.map  annot_arg_to_imm_ann arg
(* List.fold_left  (fun acc a -> acc@(annot_arg_to_imm_ann a) ) [] arg *)

let annot_arg_to_imm_ann_list (arg: annot_arg list): ann list =
  Debug.no_1 "annot_arg_to_imm_ann_list" (pr_list string_of_annot_arg) (pr_list string_of_ann) annot_arg_to_imm_ann_list arg

let annot_arg_to_imm_ann_list_no_pos (arg: (annot_arg * int) list): ann list =
  (* List.fold_left  (fun acc a -> acc@(annot_arg_to_imm_ann a) ) [] (List.map (fun (x,_) -> x ) arg) *)
  (* List.fold_left  (fun acc a -> acc@(annot_arg_to_imm_ann a) ) []  *)
  List.map (fun (x,_) -> annot_arg_to_imm_ann x ) arg

let imm_ann_to_annot_arg (a: ann): annot_arg =  mkImmAnn a

let imm_ann_to_annot_arg_list (anns: ann list): annot_arg list =
  List.map imm_ann_to_annot_arg anns
(* List.fold_left  (fun acc a -> acc@[imm_ann_to_annot_arg a] ) [] anns *)

let imm_to_view_arg (ann: heap_ann): view_arg = 
  mkAnnotArg (imm_ann_to_annot_arg (ConstAnn(ann)))

let imm_ann_to_view_arg (ann: ann): view_arg = 
  mkAnnotArg (mkImmAnn ann)

let imm_ann_to_view_arg_list (ann: ann list): view_arg list = 
  List.map (fun a -> mkAnnotArg (mkImmAnn a)) ann

let view_arg_to_imm_ann (arg: view_arg): ann =
  match arg with
  | SVArg _     -> NoAnn
  | AnnotArg a  -> annot_arg_to_imm_ann a

let view_arg_to_imm_ann_list (args: view_arg list): ann list=
  (* List.fold_left (fun acc arg -> acc@(view_arg_to_imm_ann arg)) []  args *)
  List.map view_arg_to_imm_ann args

let annot_arg_to_sv (arg: annot_arg): spec_var list =
  match arg with
  | ImmAnn a -> fv_ann a

let annot_arg_to_sv_list (args:annot_arg list): spec_var list =
  List.fold_left (fun acc a -> acc@(annot_arg_to_sv a)) [] args

let fv_annot_arg (args: (annot_arg *int) list): spec_var list =
  let anns = annot_arg_to_imm_ann_list_no_pos args in
  fv_ann_lst anns

let view_arg_to_sv (arg:view_arg): spec_var list =
  match arg with
  | SVArg sv   -> [sv]
  | AnnotArg a -> annot_arg_to_sv a

let view_arg_to_sv_list (args:view_arg list): spec_var list =
  List.fold_left (fun acc a -> acc@(view_arg_to_sv a)) [] args

let view_arg_to_annot_arg (arg:view_arg): annot_arg list =
  match arg with
  | AnnotArg arg -> [arg]
  | _            -> []

let view_arg_to_annot_arg_list (args:view_arg list): annot_arg list =
  List.fold_left (fun acc arg -> acc@(view_arg_to_annot_arg arg)) []  args

let annot_arg_to_view_arg (arg: annot_arg): view_arg =
  mkAnnotArg arg

let annot_arg_to_view_arg_list (args: annot_arg list): view_arg list =
  List.fold_left (fun acc a -> acc@[annot_arg_to_view_arg a]) [] args

let split_view_args (params: (view_arg *'a) list): spec_var list * 'a list * annot_arg list =
  let view_args,annot_args = List.partition (fun (a,_) -> is_view_var_arg a) params in
  let view_args, labels = List.split view_args in
  let view_args  = List.fold_left (fun acc arg -> acc@(view_arg_to_sv arg)) [] view_args in
  let annot_args, _ = List.split annot_args in
  let annot_args = List.fold_left (fun acc arg -> acc@(view_arg_to_annot_arg arg)) [] annot_args in
  view_args,labels,annot_args

let sv_to_annot_arg (sv:spec_var): annot_arg = ImmAnn (mkPolyAnn sv)
(* match sv with *)
(*   | SpecVar(AnnT_,_) -> ImmAnn (mkPolyAnn sv) *)
(*   | _                -> (*continue here if there are more kind of annotations *)*)

let sv_to_view_arg (sv: spec_var): view_arg =
  match sv with
  | SpecVar(AnnT, _, _) -> mkAnnotArg (sv_to_annot_arg sv)
  | _                   -> mkSVArg sv 

let sv_to_view_arg_list (svl: spec_var list): view_arg list =
  List.map sv_to_view_arg svl

let create_view_arg_list_from_map (map: view_arg list) (hargs: spec_var list) (annot: annot_arg list) = 
  try
    let hargs = sv_to_view_arg_list hargs in
    let annot = annot_arg_to_view_arg_list annot in 
    let lst = Gen.range 1 (List.length map) in
    let lst = List.combine lst map in
    let lst_sv,lst_ann = List.partition ( fun (_,a) -> is_view_var_arg a) lst in
    let lst_sv = List.combine lst_sv hargs in
    let lst_sv = List.map (fun ((no,_),harg) -> (no,harg)) lst_sv in
    let lst_ann = List.combine lst_ann annot in
    let lst_ann = List.map (fun ((no,_),ann) -> (no,ann)) lst_ann in
    let lst = lst_sv@lst_ann in
    let lst = List.sort (fun (no1,_) (no2,_) -> no1 - no2) lst in
    let lst = List.map (fun (_,a) -> a) lst in
    lst
  with Invalid_argument s -> 
    raise (Invalid_argument (s ^ " at Cpure.create_view_arg_list_from_map") )

let create_view_arg_list_from_pos_map (map: (view_arg*int) list) (hargs: spec_var list) (annot: (annot_arg*int) list) = 
  try
    (* update the annotations first *)
    let () = x_tinfo_pp ("annot: " ^(string_of_int (List.length annot)  )) no_pos in
    let () = x_tinfo_hp (add_str "annot: "  (pr_list string_of_int)) (List.map snd annot) no_pos in
    let () = x_tinfo_hp (add_str "hargs: " !print_svl)  hargs  no_pos in
    let view_args_pos = List.map (fun (va,p) -> 
        try 
          let () = Debug.ninfo_pprint ("p: " ^(string_of_int p)) no_pos in
          let (a,p) = List.find (fun (_,i) ->
              let () = Debug.ninfo_pprint ("i: " ^(string_of_int i)) no_pos in p == i) annot in
          (annot_arg_to_view_arg a, p)
        with Not_found -> (va,0)) map in
    let () = x_tinfo_pp ("view_args_pos: " ^(string_of_int (List.length view_args_pos)  )) no_pos in
    let temp_pos = Gen.range 1 (List.length view_args_pos) in
    let view_arg_temp_pos = List.combine view_args_pos temp_pos in
    let to_be_updated, already_updated = List.partition (fun ((va,p),tp) -> p == 0 ) view_arg_temp_pos in
    let () = x_tinfo_hp (add_str "to_be_updated: " string_of_int) (List.length to_be_updated) no_pos in
    let new_update = try  
        (* type: (((view_arg * int) * int) * spec_var) list *)
        let new_com = List.combine to_be_updated hargs in
        let pr = pr_list (pr_pair (pr_pair (pr_pair print_view_arg string_of_int) string_of_int) !print_sv) in
        let () = x_tinfo_hp (add_str "new_com" pr) new_com no_pos in
        List.map (fun (((va,_),p),sv) -> ((sv_to_view_arg sv,0),p) ) new_com
      with Invalid_argument s -> 
        (* TODO : to use gen_pos *)
        List.map (fun sv -> ((sv_to_view_arg sv,0),0)) hargs
        (* raise (Invalid_argument (s ^ " at Cpure.create_view_arg_list_from_pos_map 000") ) *)
    in
    let full_updated = new_update@already_updated in
    let updated_in_orig_pos = List.sort (fun (_,p1) (_,p2) -> p1 - p2) full_updated in
    let updated_in_orig_pos, _ = List.split updated_in_orig_pos in (* get rid of temp pos *)
    let updated_view_arg,_ = List.split updated_in_orig_pos in (* get rid of orig pos *)
    updated_view_arg
  with Invalid_argument s -> 
    (* raise (Invalid_argument (s ^ " at Cpure.create_view_arg_list_from_pos_map") ) *)
    (* let () = report_warning no_pos (s ^ " at Cpure.create_view_arg_list_from_pos_map") in *)
    List.map fst map

let create_view_arg_list_from_pos_map (map: (view_arg*int) list) (hargs: spec_var list) (annot: (annot_arg*int) list) =
  let pr1 = pr_list (pr_pair print_view_arg string_of_int) in
  let pr2 = pr_list (pr_pair !print_annot_arg string_of_int) in
  Debug.no_3 "create_view_arg_list_from_pos_map" pr1 !print_svl pr2 (pr_list print_view_arg)
    create_view_arg_list_from_pos_map map hargs annot

(* Ocaml compiler bug here *)
(* norm/ex25a5.slk *)
(* !!! **cpure.ml#15002:lst_sv:[] *)
(* !!! **cpure.ml#15003:lst:[] *)
(* !!! **cpure.ml#15011:**cpure.ml#15011:combine_labels:([],[]) *)
let rec combine_noexc ls1 ls2 =
  match ls1,ls2 with
  | [],_ -> []
  | _,[] -> []
  | x::xs,y::ys -> (x,y)::(combine_noexc xs ys)

let combine_labels_w_view_arg  lbl view_arg =
  try
    let no_lst = Gen.range 1 (List.length view_arg) in
    let lst = List.combine no_lst view_arg in
    let lst_sv,lst_ann = List.partition ( fun (_,a) -> is_view_var_arg a) lst in
    let () = y_tinfo_hp (add_str "lst_sv" (pr_list pr_none)) lst_sv in
    let () = y_tinfo_hp (add_str "lst" (pr_list pr_none)) lst in
    let lst_sv = combine_noexc lbl lst_sv in
    let lst_ann = List.map (fun a -> (LO.unlabelled,a)) lst_ann in
    let no_view_args = lst_sv@lst_ann in
    let no_view_args = List.sort (fun (_,(no1,_)) (_,(no2,_)) -> no1 - no2) no_view_args in
    let view_args_w_lbl = List.map (fun (l,(_,a)) -> (l,a)) no_view_args in
    view_args_w_lbl
  with r -> 
    let () = y_winfo_hp (add_str (x_loc^"combine_labels") 
                           (pr_pair (pr_list (fun (a,_)->a)) (pr_list pr_none))) (lbl,view_arg) in
    raise r

let initialize_positions_for_view_params (va: 'a list) = 
  let positions = Gen.range 1 (List.length va) in
  let va_pos = List.combine va positions in
  va_pos

(* let update_positions_for_view_params (va: 'a list) =  *)
(*   let positions = Gen.range 1 (List.length va) in *)
(*   let va_pos = List.combine va positions in *)
(*   va_pos *)

let update_positions_for_view_params_x (aa: annot_arg list) (pattern_lst: (view_arg * int) list) = 
  (* let aa_pos = List.map (fun a -> (a,0)) aa in *)
  let aa_pos = List.map (fun a -> 
      let a = annot_arg_to_view_arg a in
      let ff p = if (eq_view_arg (fst p) a) then Some (a,snd p) else None in
      let found = Gen.BList.list_find ff pattern_lst in
      match found with
      | Some p -> p
      | None   -> (a,0) ) aa in
  let aa, pos = List.split aa_pos in
  let aa = view_arg_to_annot_arg_list aa in
  let aa_pos = List.combine aa pos in
  aa_pos

let update_positions_for_imm_view_params (aa: ann list) (old_lst: (annot_arg * int) list) = 
  (* let aa_pos = List.map (fun a -> (a,0)) aa in *)
  try 
    let lst = List.combine aa old_lst in 
    let new_annot_args = List.map (fun (a, (aa,p)) -> (imm_ann_to_annot_arg a, p)) lst in new_annot_args
  with Invalid_argument s -> 
    begin
      let def_aa_pos = List.map (fun a -> (imm_ann_to_annot_arg a,0)) aa in
      Debug.info_pprint "WARNING: issue with Cpure.update_positions_for_annot_imm_params" no_pos;
      def_aa_pos
    end
(* with Invalid_argument s -> raise (Invalid_argument (s ^ "Cpure.update_positions_for_imm_view_params")) *)

let update_positions_for_imm_view_params (aa: ann list) (old_lst: (annot_arg * int) list) =
  let pr1 = pr_list string_of_ann in
  let pr2 = pr_list (pr_pair string_of_annot_arg string_of_int) in
  Debug.no_2 "update_positions_for_imm_view_params" pr1 pr2
    pr2 update_positions_for_imm_view_params aa old_lst

let update_positions_for_annot_view_params (aa: annot_arg list) (old_lst: (annot_arg * int) list) = 
  try 
    let lst = List.combine aa old_lst in 
    let new_annot_args = List.map (fun (a, (_,p)) -> (a, p)) lst in new_annot_args
  with Invalid_argument s -> 
    begin
      (* let def_aa_pos = List.map (fun a -> (a,0)) aa in *)
      Debug.info_pprint "WARNING: issue with Cpure.update_positions_for_annot_view_params" no_pos;
      old_lst
    end
(* raise (Invalid_argument (s ^ "Cpure.update_positions_for_annot_view_params")) *)


let update_positions_for_annot_view_params (aa: annot_arg list) (old_lst: (annot_arg * int) list) = 
  let pr1 = pr_list string_of_annot_arg in
  let pr2 = pr_list (pr_pair string_of_annot_arg string_of_int) in
  Debug.no_2 "update_positions_for_annot_view_params" pr1 pr2
    pr2 update_positions_for_annot_view_params aa old_lst

let apply_flist_to_annot_arg f_imm (args: annot_arg list) : annot_arg list=
  let args = annot_arg_to_imm_ann_list args in
  let args = f_imm args in
  let args = imm_ann_to_annot_arg_list args in
  args

let apply_f_to_annot_arg f (args: annot_arg list) : annot_arg list=
  let flist args = List.map f args in
  apply_flist_to_annot_arg flist args

let update_imm_args_in_view f (aa: (annot_arg * int) list): (annot_arg * int) list = 
  let new_pimm = apply_flist_to_annot_arg f (List.map fst aa) in 
  update_positions_for_annot_view_params new_pimm aa

let subst_annot_arg_no_pos sst (aa: annot_arg list): annot_arg  list = 
  let f a = subs_imm_par sst a in
  apply_f_to_annot_arg f aa

let subst_annot_arg sst (aa:  (annot_arg * int) list): (annot_arg * int) list = 
  let f a = subs_imm_par sst a in
  let new_pimm = apply_f_to_annot_arg f (List.map fst aa) in 
  update_positions_for_annot_view_params new_pimm aa

let apply_one_annot_arg (fr,t) (aa:  (annot_arg * int) list): (annot_arg * int) list = 
  let f a = apply_one_imm (fr,t) a in
  let new_pimm = apply_f_to_annot_arg f (List.map fst aa) in 
  update_positions_for_annot_view_params new_pimm aa

(* end utilities for allowing annotations as view arguments *)

(*x=null /\ x!=null*)
let is_unsat_null f=
  let neq_null_ptrs = get_neq_null_svl f in
  if neq_null_ptrs = [] then false else
    let null_ptrs = get_null_ptrs f in
    intersect_svl neq_null_ptrs null_ptrs != []

let prune_relative_unsat_disj p0 (*lhs*) base_p (*rhs*)=
  let prune_cons p=
    let ps = list_of_disjs p in
    let ps1 = List.filter (fun p1 ->
        let p2 = mkAnd p1 base_p no_pos in
        not ( is_unsat_null p2)
      ) ps in
    disj_of_list ps1 (pos_of_formula p)
  in
  let ps0,ps0a = List.partition (is_disjunct) (list_of_conjs p0) in
  let ps1 = List.map prune_cons ps0 in
  conj_of_list (ps0a@ps1) (pos_of_formula p0)

let prune_relative_unsat_disj p0 base_p=
  let pr1 = !print_formula in
  Debug.no_2 " prune_relative_unsat_disj" pr1 pr1 pr1
    (fun _ _ -> prune_relative_unsat_disj p0 base_p)
    p0 base_p

let rec nonlinear_var_list_exp (e: exp) =
  let f_e e = 
    match e with
    | Mult (e1, e2, _) ->
      let p1 = nonlinear_var_list_exp e1 in
      let p2 = nonlinear_var_list_exp e2 in
      let p = match p1, p2 with
        | [], _ -> p2
        | _, [] -> p1
        | _ -> List.concat (List.map (fun v1 -> List.map (fun v2 -> v1 @ v2) p2) p1)
      in Some p
    | Var (v, _) -> Some ([[v]])
    | _ -> None
  in fold_exp e f_e List.concat



let nonlinear_var_list_formula (f: formula) =
  let f_e e = Some (nonlinear_var_list_exp e) in
  let r = fold_formula f (nonef, nonef, f_e) List.concat in
  List.filter (fun l -> (List.length l) >= 2) r

let nonlinear_var_list_formula (f: formula) =
  let pr1 = !print_formula in
  let pr2 = pr_list !print_svl in
  Debug.no_1 "nonlinear_var_list_formula" pr1 pr2 
    nonlinear_var_list_formula f

let overapp_ptrs_x f0=
  let detect_ptr_xpure_form f sv1 sv2 a b c=
    match sv1 with
    | Var (sv ,pos) -> let () = x_ninfo_hp (add_str "xx" pr_id) "2" no_pos in
      (* let t = type_of_spec_var sv in *)
      (* let () = Debug.info_hprint (add_str "t" string_of_typ) t no_pos in *)
      if is_node_typ sv && is_num sv2 then
        let zero = IConst (0, pos) in
        (true, BForm ((Neq (sv1, zero, b), c), a))
      else (false, f)
    | _ -> (false, f)
  in
  let rec helper f= match f with
    | BForm (bf,a) ->
      let () = x_ninfo_hp (add_str "f" !print_formula) f no_pos in
      (match bf with
       | (Eq (sv1,sv2,b),c) ->
         let detected, new_f = detect_ptr_xpure_form f sv1 sv2 a b c in
         if detected then new_f else
           snd (detect_ptr_xpure_form f sv2 sv1 a b c)
       (* begin *)
       (* match sv1 with *)
       (*     | Var (sv ,pos) -> let () = x_ninfo_hp (add_str "xx" pr_id) "2" no_pos in *)
       (*           let t = type_of_spec_var sv in *)
       (*           let () = Debug.info_hprint (add_str "t" string_of_typ) t no_pos in *)
       (*             if is_node_typ sv && is_num sv2 then *)
       (*               let zero = IConst (0, pos) in *)
       (*               BForm ((Neq (sv1, zero, b), c), a) *)
       (*             else f *)
       (*     | _ -> begin *)
       (*         match sv2 with *)
       (*           | Var (sv ,pos) -> let () = x_ninfo_hp (add_str "xx" pr_id) "3" no_pos in *)
       (*             let t = type_of_spec_var sv in *)
       (*             let () = x_ninfo_hp (add_str "t" string_of_typ) t no_pos in *)
       (*             if is_node_typ sv && is_num sv1 then *)
       (*               let zero = IConst (0, pos) in *)
       (*               BForm ((Neq (sv2, zero, b), c), a) *)
       (*             else f *)
       (*           | _ -> let () = x_ninfo_hp (add_str "xx" pr_id) "4" no_pos in f *)
       (*       end *)
       (* end *)
       | _ -> let () = x_ninfo_hp (add_str "xx" pr_id) "1" no_pos in
         f
      )
    | Not _ -> f
    | Or (f1,f2,a,b) ->  Or (helper f1, helper f2,a,b)
    |  And (f1,f2, a) ->  And (helper f1, helper f2, a)
    | Exists (a, p, c,l) ->
      Exists (a, helper p, c,l)
    | Forall (a, p, c,l) ->
      Forall (a, helper p, c,l)
    | AndList l -> AndList( List.map (fun (a, p) -> (a, helper p) ) l)
  in
  helper f0

let overapp_ptrs p=
  let pr1 = !print_formula in
  Debug.no_1 "overapp_ptrs" pr1 pr1
    (fun _ -> overapp_ptrs_x p) p

let mk_self t =
  let t =
    match t with
    | None   -> Globals.null_type
    | Some t -> t
  in
  SpecVar (t, self, Unprimed)

(* collect constraints satisfying high-order "pred" and their related constraints.
   (i.e. collect a slice of constraints satisfying "pred")

   pred: constraint type, e.g is_bag_constraint, is_float_formula, is_relation_constraint.
*)
let collect_all_constraints_x (pred: formula -> bool) (f:formula) =
  let ls = split_conjunctions f in
  let ls_pred = List.filter (fun f -> pred f) ls in
  let fvars = List.concat (List.map fv ls_pred) in
  find_rel_constraints f fvars

let collect_all_constraints (pred: formula -> bool) (f:formula) =
  Debug.no_1 "collect_all_constraints"
    !print_formula !print_formula
    (fun _ -> collect_all_constraints_x pred f) f

(*
 v=e --> v & e | !v & !e
 e1 = e2 --> e1 & e2 | !(e1) & !e2
 e1!=e2 <--> (e1 & !e2 | !e2 & e1)
*)
let transform_bexpr_pf a lbl  pf0=
  let f0 = BForm ((pf0,a), lbl) in
  let rec recf pf=match pf with
    | Eq (e1,e2,p) -> begin
        match e1,e2 with
        | Var (s1,p1), Var (s2,p2) ->
          if type_of_spec_var s1 = Bool && type_of_spec_var s2 = Bool then
            let bsv1 = BVar (s1,p1) in
            let bsv2 = BVar (s2,p2) in
            let p1 = BForm ((bsv1,a), lbl) in
            let p2 = BForm ((bsv2,a), lbl) in
            let p11 = And (p1,p2, p) in
            let p22 = And (Not (p1, lbl,p), Not (p2,lbl,p), p) in
            Or (p11,p22, lbl, p)
          else f0
        | _ -> f0
      end
    | Neq (e1,e2,p) -> begin
        match e1,e2 with
        | Var (s1,p1), Var (s2,p2) ->
          if type_of_spec_var s1 = Bool && type_of_spec_var s2 = Bool then
            let bsv1 = BVar (s1,p1) in
            let bsv2 = BVar (s2,p2) in
            let p1 = BForm ((bsv1,a), lbl) in
            let p2 = BForm ((bsv2,a), lbl) in
            let p11 = And (Not (p1, lbl,p),p2, p) in
            let p22 = And (p1, Not (p2,lbl,p), p) in
            Or (p11,p22, lbl, p)
          else f0
        | _ -> f0
      end
    | _ -> f0
  in
  recf pf0

let transform_bexpr_x p0=
  let rec recf p= match p with
    | BForm  ((pf, a), lbl) -> transform_bexpr_pf a lbl pf
    | And  (f1, f2, p) ->  And  (recf f1, recf f2, p)
    | AndList ps -> AndList (List.map (fun (a,f1) -> (a, recf f1)) ps)
    | Or (f1, f2, lbl, p) -> Or (recf f1, recf f2, lbl, p)
    | Not (f1, lbl, p) -> Not (recf f1, lbl, p)
    | Forall (sv, f1, lbl, p) -> Forall (sv, recf f1, lbl, p)
    | Exists (sv, f1, lbl, p ) -> Exists (sv, recf f1, lbl, p )
  in
  recf p0

let transform_bexpr p=
  let pr1 = !print_formula in
  Debug.no_1 "CP.transform_bexpr" pr1 pr1
    (fun _ -> transform_bexpr_x p) p

let rec compare_term_ann a1 a2 =
  match a1, a2 with 
  | Term, Term -> 0
  | Loop _, Loop _ -> 0
  | MayLoop _, MayLoop _ -> 0
  | Fail f1, Fail f2 -> compare_term_fail f1 f2
  | TermU u1, TermU u2 -> compare_uid u1 u2
  | TermR u1, TermR u2 -> compare_uid u1 u2
  | _ -> 1

and compare_uid u1 u2 = 
  let cid = compare u1.tu_id u2.tu_id in
  if cid != 0 then cid
  else String.compare u1.tu_sid u2.tu_sid

and compare_term_fail f1 f2 = 
  match f1, f2 with
  | TermErr_May, TermErr_May -> 0
  | TermErr_Must, TermErr_Must -> 0
  | _ -> 1

let eq_term_ann a1 a2 = 
  compare_term_ann a1 a2 == 0

let eq_uid u1 u2 = 
  compare_uid u1 u2 == 0

let rec is_MayLoop ann = 
  match ann with
  | MayLoop _ -> true
  | TermU uid -> begin
      match uid.tu_sol with
      | None -> false
      | Some (s, _) -> is_MayLoop s
    end
  | _ -> false 

let rec is_Loop ann = 
  match ann with
  | Loop _ -> true
  | TermU uid -> is_Loop_uid uid
  | _ -> false

and is_Loop_uid uid = 
  match uid.tu_sol with
  | None -> false
  | Some (s, _) -> is_Loop s

let rec is_Term ann = 
  match ann with
  | Term -> true
  | TermU uid -> begin
      match uid.tu_sol with
      | None -> false
      | Some (s, _) -> is_Term s
    end
  | _ -> false

let is_TermU ann =
  match ann with
  | TermU _ -> true
  | _ -> false

let is_unknown_term_ann ann =
  match ann with
  | TermU uid 
  | TermR uid -> begin
      match uid.tu_sol with
      | None -> true
      | _ -> false
    end
  | _ -> false



let cond_of_term_ann ann =
  match ann with
  | TermU uid -> uid.tu_cond
  | TermR uid -> uid.tu_cond
  | _ -> mkTrue no_pos

let fn_of_term_ann ann =
  match ann with
  | TermU uid -> uid.tu_fname
  | TermR uid -> uid.tu_fname
  | _ -> ""

let call_num_of_term_ann ann =
  match ann with
  | TermU uid -> uid.tu_call_num
  | TermR uid -> uid.tu_call_num
  | _ -> 0

let args_of_term_ann ann =
  match ann with
  | TermU uid -> uid.tu_args
  | TermR uid -> uid.tu_args
  | _ -> []

let fv_of_term_ann ann =
  List.concat (List.map afv (args_of_term_ann ann))

let uid_of_term_ann ann =
  match ann with
  | TermU uid
  | TermR uid -> Some uid
  | _ -> None

let rec cex_of_term_ann ann = 
  match ann with
  | MayLoop cex -> cex
  | Loop cex -> cex
  | TermU uid -> begin
      match uid.tu_sol with
      | None -> None
      | Some (s, _) -> cex_of_term_ann s
    end
  | _ -> None

let rec cex_of_term_ann_list anns = 
  match anns with
  | [] -> None
  | m::ms -> 
    let mcex = cex_of_term_ann m in
    match mcex with
    | None -> cex_of_term_ann_list ms
    | Some _ -> mcex

let merge_term_cex c1 c2 = 
  match c1, c2 with
  | None, None -> None
  | None, Some _ -> c2
  | Some _, None -> c1
  | Some t1, Some t2 ->
    Some ({ tcex_trace = t1.tcex_trace @ t2.tcex_trace; })

let mkUTPre uid = 
  TermU { uid with tu_sid = uid.tu_sid ^ "pre" }

let mkUTPost uid = 
  TermR { uid with
          tu_id = fresh_int (); 
          tu_sid = uid.tu_sid ^ "post" }

let collect_term_ann_fv_pure f =
  let f_b b = 
    let (p, _) = b in match p with
    | LexVar tinfo -> Some (fv_of_term_ann tinfo.lex_ann)
    | _ -> Some []
  in fold_formula f (nonef, f_b, nonef) List.concat

let is_shape f=
  let svl = fv f in
  List.for_all (fun sv -> (is_node_typ sv)) svl

let contains_undef (f:formula) =
  let afv = all_vars f in
  List.fold_left (fun acc sv -> acc || (is_undef_typ (type_of_spec_var sv)) ) false afv 

let syn_checkeq = ref(fun (ls:ident list) (a:formula) (c:formula) (m: ((spec_var * spec_var) list) list) -> (true,([]: ((spec_var * spec_var) list) list)))

let is_exists_svl v vs =
  List.exists (eq_spec_var v) vs 

let exp_to_sv e = match (conv_exp_to_var e) with
  | Some (sv,_) -> sv
  | None -> 
    let () = y_winfo_pp " UNKNOWN spec_var used " in
    let () = y_dinfo_hp (add_str "exp is var?" !print_exp) e in
    unknown_spec_var


let rec gen_cl_eqs pos svl p_res=
  match svl with
    | [] -> p_res
    | sv::rest ->
          let new_p_res = List.fold_left (fun acc_p sv1 ->
              let p = mkEqVar sv sv1 pos in
              mkAnd acc_p p pos
          ) p_res rest in
          gen_cl_eqs pos rest new_p_res


let mk_eq_zero a1 = 
  let a1 = mkVar a1 no_pos in
  mk_bform (Eq (a1, mkIConst 0 no_pos,no_pos))

let mk_eq_null sv = 
  let v = mkVar sv no_pos in
  mk_bform (Eq (v, Null no_pos, no_pos))

let mk_eq_vars v1 v2 = 
  let v1 = mkVar v1 no_pos in
  let v2 = mkVar v2 no_pos in
  mk_bform (Eq (v1, v2, no_pos))

let mk_eq_exp v1 v2 = 
  mk_bform (Eq (v1, v2, no_pos))

let mk_max a a1 a2 = 
  let a = mkVar a no_pos in
  let a1 = mkVar a1 no_pos in
  let a2 = mkVar a2 no_pos in
  mk_bform (mkEqMax a a1 a2 no_pos)


let mkEqExp_raw (ae1 : exp) (ae2 : exp) pos :formula =
  mk_bform (Eq (ae1, ae2, pos))

let mk_sum a a1 a2 = 
  let lhs = mkVar a no_pos in
  let a1 = mkVar a1 no_pos in
  let a2 = mkVar a2 no_pos in
  let rhs = mkAdd a1 a2 no_pos in
  mkEqExp_raw lhs rhs no_pos

let mk_inc lhs rhs = 
  let lhs = mkVar lhs no_pos in
  let rhs = mkVar rhs no_pos in
  let rhs = mkAdd rhs (mkIConst 1 no_pos) no_pos in
  mkEqExp_raw lhs rhs no_pos


let is_AndList f =
  let rec aux f =
    match f with
      | AndList _ -> true
      | Or (lt,rt,_,_) -> (aux lt) || (aux rt)
      | _ -> false
  in aux f

(* let pr = drop_nonlinear_formula pf in *)

let tmp_mult_var = mk_spec_var "_mult_var"

let mk_fresh_sv v = 
  match v with
  | SpecVar (t, i, p) ->
    SpecVar (t, fresh_old_name i, p) 

(* this procedure is meant to extract multiplication
   replacing them by fresh_var *)
let extract_mult (f:formula) : (formula * ((spec_var * exp * exp) list)) = 
  let stk = new Gen.stack in
  let helper f =
    let f_f f = None in
    let f_bf bf = None in
    let f_e e = match e with
      | Mult(a,b,l) -> 
        let new_v = mk_fresh_sv (tmp_mult_var) in
        let () = stk # push (new_v,a,b) in
        Some (Var(new_v,l))
      | _ -> Some(e) in
    map_formula f (f_f,f_bf,f_e) in 
  let f = helper f in
  let subs = stk # get_stk in
  (f,subs)

let extract_mult (f:formula) : (formula * ((spec_var * exp * exp) list)) =
  let pr = !print_formula in
  let pr2 = pr_pair pr (pr_list (pr_triple !print_sv !print_exp !print_exp)) in
  Debug.no_1 "extract_mult" pr pr2 extract_mult f


(* let map_formula (e: formula) (f_f, f_bf, f_e) : formula = *)
  
let extr_eqn (f:formula)  = 
  let stk = new Gen.stack in
  let rec helper f =
    let f_f f = None in
    let f_bf bf = match bf with
      | (Eq (e1,e2,_),_) -> 
        let () = stk # push (BForm (bf,None))(* (e1,e2) *) in
        Some bf
      | _ -> Some bf in
    let f_e e = Some e in
    map_formula f (f_f,f_bf,f_e) in
  let _ = helper f in
  stk # get_stk

let rec get_base e =
  match e with
  | Add(IConst _,e2,_) | Add(e2, IConst _,_) -> get_base e2
  | Add((Var(v,_) as e1),e2,_) | Add(e2,(Var(v,_) as e1),_) 
    -> if is_ptr_arith (typ_of_sv v) then e1 else get_base e2
  | _ -> e

let get_base e =
  let pr_exp = !print_exp in
  Debug.no_1 "get_base" pr_exp pr_exp get_base e

let get_ptr e1 e2 =
  (* let () = y_tinfo_hp (add_str "get_ptr(e1)" !print_exp) e1 in *)
  (* let () = y_tinfo_hp (add_str "get_ptr(e2)" !print_exp) e2 in *)
  let e1 = get_base e1 in
  let e2 = get_base e2 in
  match e1,e2 with
  | Var(v1,_),Var(v2,_) -> 
    if is_ptr_arith (typ_of_sv v1) then Some v1
    else if is_ptr_arith (typ_of_sv v2) then Some v2
    else None
  | Var(v1,_),_ -> 
     if is_ptr_arith (typ_of_sv v1) then Some v1 else None
  | _,Var(v1,_) -> 
    if is_ptr_arith (typ_of_sv v1) then Some v1 else None
  | _,_ -> None

let to_sub e1 e2 p =
  match e1,e2 with
    | IConst (i1,_),IConst(i2,_) -> IConst(i1-i2,p)
    | e,IConst (i,_) -> if i==0 then e else Subtract(e1,e2,p)
    | _,_ -> Subtract(e1,e2,p)

let to_add e1 e2 p =
  match e1,e2 with
    | IConst (i1,_),IConst(i2,_) -> IConst(i1+i2,p)
    | IConst (i,_),e | e,IConst (i,_) -> if i==0 then e else Add(e1,e2,p)
    | _,_ -> Add(e1,e2,p)

(* this gets base+offset, throws exception otherwise  *)
let rec get_base2 e =
  match e with
  | Var(v,p) -> 
        if is_ptr_arith (typ_of_sv v) then (v,IConst(0,no_pos))
        else failwith "get_base2 failed 1"
  | Add(e1,e2,p) ->
        (try
          let (v1,e1) = get_base2 e1 
          in (v1,to_add e1 e2 p)
        with _ -> 
            let (v2,e2) = get_base2 e2 
            in (v2, to_add e1 e2 p))
  | Subtract(e1,e2,p) ->
        let (v1,e1) = get_base2 e1 
        in (v1,to_sub e1 e2 p)
  | _ -> failwith "get_base2 failed 2"

let norm_base lhs rhs =
  try
    match lhs,rhs with
      | Var(v,_),e | e,Var(v,_) ->
            let (v2,a2) = get_base2 e in
            Some (v,v2,a2)
      | e1,e2 -> 
            let (v1,a1) = get_base2 e1 in
            let (v2,a2) = get_base2 e2 in
            Some (v1,v2,to_sub a2 a1 no_pos)
  with _ -> None

let norm_base lhs rhs =
  let pr_3 (a,b,c) = "(,"^(!print_sv a)^","^(!print_sv b)^","^(!print_exp c)^")" in
  let pr = pr_option pr_3 in
  Debug.no_2 "norm_base_helper" !print_exp !print_exp pr norm_base lhs rhs

let norm_base lhs rhs =
  let r = norm_base lhs rhs in
  match r with
    | Some(v1,v2,IConst(i,_))
            -> if i==0 then None
            else r
    | _ -> r

let norm_base lhs rhs =
  let pr_3 (a,b,c) = "(,"^(!print_sv a)^","^(!print_sv b)^","^(!print_exp c)^")" in
  let pr = pr_option pr_3 in
  Debug.no_2 "norm_base" !print_exp !print_exp pr norm_base lhs rhs


(* extraction here is incomplete for base! *)
(* extr_ptr_eqn@3 *)
(* extr_ptr_eqn inp1 : 0<=i:NUM & a:arrI=2+i:NUM & x:arrI=2+i:NUM *)
(* extr_ptr_eqn@3 EXIT:([],[ x:arrI=2+i:NUM, a:arrI=2+i:NUM]) *)
(* to return (ptr,v) from ptr=v+c and eq1=eq2 equations *)

let extr_ptr_eqn_old (f:formula)  = 
  let stk = new Gen.stack in
  let stk_ptr = new Gen.stack in
  let rec helper f =
    let f_f f = None in
    let f_bf bf = 
      let pf = BForm (bf,None) in
      (* what about Sub(e1,e2) *)
      (* extr_ptr_eqn@7 *)
      (* extr_ptr_eqn inp1 : x=(self+n)-1 & 0<=i *)
      (* extr_ptr_eqn@7 EXIT:([],[ x=(self+n)-1]) *)
      (* !!! **cpure.ml#15973:cannot handle ptr: x+1=n+base *)
      (* !!! **cpure.ml#15973:cannot handle ptr: i_137=i *)
      (* !!! **cpure.ml#15973:cannot handle ptr: x_139+1=flted_13_85+base *)
      (* !!! **cpure.ml#15973:cannot handle ptr: x=(self+n)-1 *)
      match bf with
        | (Eq (Var(v1,_),Add(e1,e2,_),_),_)
        | (Eq (Add(e1,e2,_),Var(v1,_),_),_)
            ->
              begin
                match get_ptr e1 e2 with
                  | Some v2 -> stk_ptr # push (v1,v2)
                  | _ -> ()
              end;
                (* let () = y_tinfo_hp (add_str "branch1" !print_formula) pf in *)
                let () = stk # push pf in
                Some bf
        | (Eq _,_) ->
              let () = y_winfo_hp (add_str "cannot handle ptr" !print_formula) pf in
              let () = stk # push pf in
              let () = y_tinfo_hp (add_str "other" !print_formula) pf in
              Some bf
        | _ -> None in
    let f_e e = Some e in
    map_formula f (f_f,f_bf,f_e) in
  let _ = helper f in
  (stk_ptr # get_stk,stk # get_stk)
 
let extr_ptr_eqn (f:formula)  = 
  let stk = new Gen.stack in
  let stk_ptr = new Gen.stack in
  let rec helper f =
    let f_f f = None in
    let f_bf bf = 
      let pf = BForm (bf,None) in
      match bf with
        | (Eq(e1,e2,_),_) -> 
              let r = norm_base e1 e2 in
              (match r with
                | Some(v1,v2,e) -> stk_ptr # push (v1,v2)
                | None -> ()); stk # push pf; Some bf
        | _ -> None in
    let f_e e = Some e in
    map_formula f (f_f,f_bf,f_e) in
  let _ = helper f in
  (stk_ptr # get_stk,stk # get_stk)

let extr_ptr_eqn_old (f:formula)  = 
  let pr = !print_formula in
  let pr_sv = !print_sv in
  Debug.no_1 "extr_ptr_eqn_old" pr (pr_pair (pr_list (pr_pair pr_sv pr_sv)) (pr_list pr)) extr_ptr_eqn_old f

let extr_ptr_eqn (f:formula)  =
  (* let _ = extr_ptr_eqn_old f in *)
  let pr = !print_formula in
  let pr_sv = !print_sv in
  Debug.no_1 "extr_ptr_eqn" pr (pr_pair (pr_list (pr_pair pr_sv pr_sv)) (pr_list pr)) extr_ptr_eqn f

let simplify_eqn (f:formula)  = 
  let rec helper f =
    let f_f f = None in
    let f_bf bf = 
      match bf with
      | (Eq (Var(v1,_),Var(v2,_),_),_) -> 
         if eq_spec_var v1 v2 then Some (BConst(true,no_pos),None)
         else Some bf
      | (Neq (Var(v1,_),Var(v2,_),_),_) -> 
         if eq_spec_var v1 v2 then Some (BConst(false,no_pos),None)
         else Some bf
      | _ -> Some bf 
    in
    let f_e e = Some e in
    map_formula f (f_f,f_bf,f_e) in
  helper f

let mkLtVars a1 a2 =
  BForm ((Lt (Var (a1,no_pos),Var(a2,no_pos), no_pos),None),None)

let mkEqVars a1 a2 =
  BForm ((Eq (Var (a1,no_pos),Var(a2,no_pos), no_pos),None),None)

let mk_is_baseptr d rhs_ptr =
  BForm ((Gte (Var (d,no_pos),Var(rhs_ptr,no_pos), no_pos),None),None)

let is_Or f = match f with
  | Or _ -> true
  | _ -> false


let pick_baseptr (pf : formula) (* : (spec_var * spec_var) list *) =
  let stk = new Gen.stack in
  let pick_ptr p = 
    let vs = fv p in
    let (int_vs,ptr_vs) = List.partition (fun v -> is_num_or_int_typ v) vs in
    (* if int_vs!=[] then  *)
    match ptr_vs with
      | [v1;v2] -> Some [(v1,v2)]
      | _ -> None
    (* else None *) in 
  let f_bf bf =
    let pf, lbl = bf in
    (match pf with
     | Eq (e1, e2, pos) -> pick_ptr (BForm ((pf,None),None))
     | RelForm (sv,arg::_,_) -> 
           begin
             let flag = is_baseptr_var sv in
             let () = y_tinfo_hp (add_str "base_ptr" (pr_pair string_of_bool !print_sv)) (flag,sv) in
             if is_baseptr_var sv then
               begin
                 match (get_exp_var arg) with
                   | Some v -> stk # push v
                   | _ -> () 
               end;
             None
           end
     | _ -> None)
  in
  let f_comb = List.concat in 
  let vs = fold_formula pf (nonef,f_bf,nonef) f_comb in
  (vs,stk # get_stk)

let pick_baseptr pf =
  let pr = !print_sv in
  let pr_out = pr_pair (pr_list (pr_pair pr pr)) !print_svl in
  Debug.no_1 "pick_baseptr" !print_formula pr_out pick_baseptr pf

let find_baseptr_equiv lst bptr =
  let emap = EMapSV.build_eset lst in
  List.map (fun x -> 
      let vs = EMapSV.find_equiv_all x emap in
      (x,intersect_svl vs bptr)
  ) bptr

let find_baseptr_equiv lst bptr =
  let pr2 = !print_svl in
  let pr1 = pr_list (pr_pair !print_sv !print_sv) in
  Debug.no_2 "find_baseptr_equiv" pr1 pr2 (pr_list (pr_pair !print_sv pr2)) find_baseptr_equiv lst bptr

(* this finds baseptrs for existential instantiation *)
let inst_baseptr rhs_base_ptr_vs lhs_w_rhs_inst ex_inst =
  let (pairs,baseptr) = x_add_1 pick_baseptr lhs_w_rhs_inst in
  let exist_baseptr = intersect_svl ex_inst rhs_base_ptr_vs in
  let baseptr = baseptr@exist_baseptr in
  let base_eq = x_add find_baseptr_equiv pairs baseptr in
  let base_eq = List.filter (fun (v,_) -> (diff_svl [v] exist_baseptr)==[]) base_eq in
  (* let (lhs_pair,inst_pair) = List.partition (fun (v1,v2) -> intersect_svl [v1;v2] ex_inst==[]) pairs in *)
  let rec mk_pair lst =
    match lst with 
      | x::((y::_) as rest) -> (x,y)::(mk_pair rest)
      | _ -> [] in
  let lst_of_inst = List.concat (List.map (fun (_,lst) -> mk_pair lst) base_eq) in
  (* let inst_pair = List.map (fun (v1,v2) ->  *)
  (*     if List.exists (eq_spec_var v1) ex_inst then (v2,v1) else (v1,v2)) inst_pair in *)
  (* let choose_base lhs lhs_pairs =  *)
  (*   let rec aux lst =  *)
  (*     match lst with *)
  (*     | [] -> [] *)
  (*     | (v1,v2)::lst ->  *)
  (*       if !tp_imply lhs (mk_is_baseptr v1 v2) then (v1,v2)::(aux lst) *)
  (*       else if !tp_imply lhs (mk_is_baseptr v2 v1) then (v2,v1)::(aux lst) *)
  (*       else aux lst *)
  (*   in aux lhs_pairs in *)
  (* let find lst v =  *)
  (*   try  *)
  (*     Some (snd (List.find (fun (v1,_) -> eq_spec_var v1 v) lst)) *)
  (*   with _ -> None in *)
  (* let choose_inst cb inst_pair =  *)
  (*   let rec aux ip = match ip with *)
  (*     | [] -> [] *)
  (*     | (cv,base1)::lst -> begin *)
  (*         match (find cb cv) with *)
  (*         | Some base2 -> (base1,base2)::(aux lst) *)
  (*         | _ -> [] *)
  (*       end  *)
  (*   in aux inst_pair *)
  (* in *)
  (* (\* choosing those with a (ptr,base) *\) *)
  (* let common_base_lst = choose_base lhs_w_rhs_inst lhs_pair in *)
  (* let lst_of_inst = choose_inst common_base_lst inst_pair in *)
  let lhs_w_rhs_inst2 = List.fold_left (fun acc (v1,v2) ->
      mkAnd acc (mkEqVars v1 v2) no_pos
    ) lhs_w_rhs_inst lst_of_inst in 
  let pr_lst_pair = pr_list (pr_pair !print_sv !print_sv) in
  (* let () =  y_tinfo_hp (add_str "common_base_lst" pr_lst_pair) common_base_lst in *)
  (* let () =  y_tinfo_hp (add_str "inst_pair" pr_lst_pair) inst_pair in *)
  let () =  y_tinfo_hp (add_str "lst_of_inst" pr_lst_pair) lst_of_inst in
  let () =  y_tinfo_hp (add_str "lhs_w_rhs_inst2" !print_formula) lhs_w_rhs_inst2  in
  lhs_w_rhs_inst2


let inst_baseptr rhs_base_ptr_vs lhs_w_rhs_inst ex_inst  =
  let pr = !print_formula in
  Debug.no_2 "inst_baseptr" pr !print_svl pr (inst_baseptr rhs_base_ptr_vs) lhs_w_rhs_inst ex_inst
