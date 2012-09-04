open Cpure
open Cformula
open Gen.Basic
open Globals
open Cast

module CP = Cpure
module DD = Debug

type term_type =
	| Base (* Where termination or non-termination can be determined *)
	| Rec of ident (* Name of recursive callee *)

type term_res =
	| Loop of int
	| Term of int
	| Unknown of term_unk_info

and term_unk_info = {
	unk_id				: int;
	unk_callee		: ident;
	unk_params		: (spec_var list * spec_var list);
	unk_trans_ctx	: CP.formula;
}

and term_ctx = {
	t_type 				: term_type;
	(* Original Context associating with base cases or recursive cases *)
	t_ctx 				: list_failesc_context;	
	(* Each element of t_pure_ctx is a separate context with the assoc path *)
	t_pure_ctx		: (path_trace * CP.formula) list;
	(* Args list and Params list *)
	t_params			: (spec_var list * spec_var list); 
	(* Pure condition of function parameters for base cases or recursive cases *)
	(* Generated by simplifying t_ctx via exist elimination                    *)
	t_cond_pure 	: (path_trace * CP.formula * term_res) list; 
}

and list_term_ctx = term_ctx list

(* The structure below supports path-sensitive analysis for termination *)
and term_spec = 
	| TBase of term_spec_base
	| TCase of term_spec_case 
	| TSeq of term_spec_seq

and term_spec_base = {
	term_base_res	: term_res;
	term_base_cond: CP.formula;
}

and term_spec_case = (CP.formula * term_spec) list
(* {                                          *)
(* 	term_case_then: (CP.formula * term_spec); *)
(* 	term_case_else: (CP.formula * term_spec); *)
(* }                                          *)

and term_spec_seq = {
	term_seq_fst	: term_spec; 
	term_seq_snd	: term_spec;	
}

and term_trans_constraint = {
	trans_src			: term_res;
	(* trans_src_cond: CP.formula list; *)
	trans_dst			: term_res;	
	(* trans_dst_cond: CP.formula list; *)
	(* trans_subst		: (spec_var list * spec_var list); *)
	(* trans_ctx			: CP.formula; *)
	(* trans_path		: path_trace; *)
}

let term_constr_tbl : ((int * int), term_trans_constraint) Hashtbl.t = Hashtbl.create 10

let term_spec_tbl : (ident, term_spec) Hashtbl.t = Hashtbl.create 10

(* let term_ctx_tbl : (ident, list_term_ctx) Hashtbl.t = Hashtbl.create 10 *)

type utils = {
	is_sat				: CP.formula -> bool;
	imply					: CP.formula -> CP.formula -> bool;
	simplify			: CP.formula -> CP.formula;
	fixcalc				: string -> spec_var list -> spec_var list -> CP.formula -> (CP.formula list);
}

(* Cprinter Utilities *)
let print_path_trace = ref (fun (c: path_trace) -> "Printer has not been initialized.")
let print_pure_formula = ref (fun (c: CP.formula) -> "Printer has not been initialized.")
let print_pure_exp = ref (fun (c: CP.exp) -> "Printer has not been initialized.")
let print_term_spec = ref (fun (c: term_spec) -> "Printer has not been initialized.")
let print_term_ctx = ref (fun (c: term_ctx) -> "Printer has not been initialized.")
let print_term_spec = ref (fun (c: term_spec) -> "Printer has not been initialized.")
let print_term_res = ref (fun (c: term_res) -> "Printer has not been initialized.")
let print_term_trans_constraint = ref (fun (c: term_trans_constraint) -> "Printer has not been initialized.")
let print_term_cond_pure = ref (fun (c: path_trace * CP.formula * term_res) -> "Printer has not been initialized.")

(* Debugging Utilities *)
let info_hprint str pr f = DD.info_hprint (add_str str pr) f no_pos
let info_pprint str = DD.info_pprint str no_pos

let partition_term_ctx tctx = 
	List.partition (fun ctx -> match ctx.t_type with
	| Base -> true | _ -> false) tctx
	
let collect_path_trace_term_ctx tctx =
	collect_path_trace_list_failesc_context tctx.t_ctx 
	
let id_of_term_res = function
	| Term i -> i
	| Loop i -> i
	| Unknown unk -> unk.unk_id

(* If the path trace of a base context is a SUPERSET of *)
(* the path trace of a recursive context, then the      *)
(* recursive call is met BEFORE the return statement    *)
(* so that these labels and their associated contexts   *)
(* should be removed in base context                    *)
let remove_incorrect_base_term_ctx tctx list_lbl =
	{ tctx with t_ctx = match tctx.t_type with
	| Base -> List.map (fun (fail_c, esc_c, succ_c) ->
			let succ_c = List.filter (fun (lbl, _) -> 
				not (List.exists (fun l -> Gen.BList.subset_eq (=) l lbl) list_lbl)) succ_c in
			(fail_c, esc_c, succ_c)) tctx.t_ctx
	| Rec _ -> tctx.t_ctx}
	
let remove_incorrect_base_list_term_ctx tctx =
	let bs, rc = partition_term_ctx tctx in
	(* Path traces of recursive calls *)
	let list_rec_lbl = List.concat (List.map collect_path_trace_term_ctx rc) in
	List.map (fun ctx -> remove_incorrect_base_term_ctx ctx list_rec_lbl) tctx
	
let remove_unsat_ctx_list_term_ctx tctx =
	List.map (fun ctx -> 
		{ctx with t_ctx = remove_unsat_succ_ctx_list_failesc_context ctx.t_ctx}) tctx
	
let remove_empty_ctx_list_term_ctx tctx = 
	let tctx = List.map (fun ctx -> 
		{ctx with t_ctx = remove_empty_succ_ctx_list_failesc_context ctx.t_ctx}) tctx in
	List.filter (fun ctx -> not (ctx.t_ctx = [])) tctx

let remove_duplicate_ctx_list_term_ctx tctx =
	List.fold_left (fun a ctx -> if (List.mem ctx a) then a else a @ [ctx]) [] tctx

let remove_duplicate_path_trace pt = 
	List.fold_left (fun a p ->
		if (List.mem p a) then a else a @ [p]) [] pt

(* Get the pure condition from context *)
(* and assign Term or Unknown for Base *)
(* and Rec, resp.                      *)
let update_cond_pure_term_ctx	tctx =
	let lf = collect_formula_with_path_list_failesc_context tctx.t_ctx in
	let lpf = List.concat (List.map (fun (lbl, f) -> 
		let lbl = remove_duplicate_path_trace lbl in
		List.map (fun pf -> (lbl, pf)) (pure_of_formula f)) lf) in
	{tctx with 
		t_pure_ctx = lpf;
		t_cond_pure = List.map (fun (pt, f) ->
			match tctx.t_type with
			| Base -> (pt, f, Term 0)
			| Rec c ->
				let unk = Unknown {
					unk_id = 0;
					unk_callee = c;
					unk_params = tctx.t_params;
					unk_trans_ctx = f; } in 
				(pt, f, unk)) lpf;}
	
let update_cond_pure_list_term_ctx tctx = 
	List.map update_cond_pure_term_ctx tctx
	
let get_method_args proc =
	let farg_types, farg_names = List.split proc.proc_args in	
	List.map2 (fun n t -> CP.SpecVar (t, n, Unprimed)) farg_names farg_types

(* Simplify the termination context to get *)
(* the conditions on method's arguments    *)
let simplify_t_cond_pure args (pt, f, t_res) =
	let qsv = diff_svl (CP.fv f) args in
	(* a!=b has already been transformed to a<b | a>b by Omega *)
	let simpl_f = mkExists_with_simpl Omega.simplify qsv f None no_pos in
	List.map (fun f -> (pt, f, match t_res with
	| Unknown unk -> (if unk.unk_id != 0 then t_res else Unknown { unk with unk_id = (fresh_int ()); })
	| Term 0 -> Term (fresh_int ())
	| _ -> t_res)) (CP.list_of_disjs simpl_f)
		
let simplify_cond_pure_term_ctx args tctx =
	{tctx with t_cond_pure = List.concat (List.map (simplify_t_cond_pure args) tctx.t_cond_pure);}
	
let simplify_cond_pure_list_term_ctx proc tctx =
	let farg_spec_vars = get_method_args proc in
	List.map (simplify_cond_pure_term_ctx farg_spec_vars) tctx
	
let sort_path_trace_by_order cl =
	let rec comp pt1 pt2 = match pt1, pt2 with
	| [],[] -> 0
	| [],xs -> -1
	| xs,[] -> 1
	| ((a1,_),b1)::zt1, ((a2,_),b2)::zt2 -> 
			if (a1 > a2) then 1
			else if (a1 < a2) then -1
			else begin
				if (b1 > b2) then 1
				else if (b1 < b2) then -1
				else comp zt1 zt2
			end
	in List.sort (fun (pt1, _, _) (pt2, _, _) -> comp pt1 pt2) cl
	
(* BUGS [ps-1d.ss]: exists(x':x'=x & MayLoop) |- exists(x':x'=x & MayLoop) --> false *)	
let rec partition_path_trace utils cl =
	let sml_pt, sml_c, _ = List.hd cl in
	(* A; B is a sequence if pathA subseteq pathB and condB |- condA, *)
	let sml_seq, others = List.partition (fun (pt, c, _) -> 
		(Gen.BList.subset_eq (=) sml_pt pt) && 
		(utils.imply c sml_c)) cl in
	if others = [] then [(sml_c, sml_seq)]
	else
		let par_others = partition_path_trace utils others in
		[(sml_c, sml_seq)] @ par_others
	
let mkTBase cond tres =
	TBase { term_base_res = tres; term_base_cond = cond; }
	
let mkTSeq fst snd =
	TSeq { term_seq_fst = fst; term_seq_snd = snd; }
	
(* let mkTCase th el =                                  *)
(* 	TCase { term_case_then = th; term_case_else = el; } *)

let mkTCase cl = TCase cl
	
let rec construct_term_spec utils cases =
	(* Note 1: If cases is empty then the program does not contain any *)
	(* recursive call, it should terminate                             *)
	(* Note 2: If there is ([], true, UNK) then the program contains   *)
	(* a recursive call without base case, it should not terminates    *)
	if cases = [] then mkTBase (CP.mkTrue no_pos) (Term (fresh_int()))
	else 
		let par_cases = partition_path_trace utils cases in
		if par_cases = [] then mkTBase (CP.mkTrue no_pos) (Term (fresh_int()))
		else 
			TCase (List.map (fun (cond, seq) -> 
				(cond, construct_seq_term_spec utils seq)) par_cases)

and construct_seq_term_spec utils cases =
	let pfst, cfst, rfst = List.hd cases in
	let cont = List.tl cases in
	let bfst = mkTBase cfst rfst in 
	if (cont = []) then bfst
	else mkTSeq bfst (construct_term_spec utils cont)
	
(* Construct case spec of termination from termination context *)
(* TODO: Do we need to check case coverage? *)		
let term_spec_of_list_term_ctx utils tctx =
	let cases = List.concat (List.map (fun ctx -> ctx.t_cond_pure) tctx) in
	let cases = sort_path_trace_by_order cases in
	let _ = print_endline (pr_list !print_term_cond_pure cases) in
	construct_term_spec utils cases	
	
(* Look up termination context and spec *)
(* let look_up_term_ctx mn = Hashtbl.find term_ctx_tbl mn *)
	
let look_up_term_spec mn = Hashtbl.find term_spec_tbl mn

let rec rename_term_spec (fsv, tsv) (tspec: term_spec) =
	match tspec with
	| TBase b -> TBase { b with term_base_cond = CP.subst_avoid_capture fsv tsv b.term_base_cond; }
	| TSeq s -> TSeq { 
		term_seq_fst = rename_term_spec (fsv, tsv) s.term_seq_fst;
		term_seq_snd = rename_term_spec (fsv, tsv) s.term_seq_snd; }
	| TCase c -> TCase (List.map (fun (cc, sc) ->
		(CP.subst_avoid_capture fsv tsv cc, rename_term_spec (fsv, tsv) sc)) c) 

(*****************************************************)
(* Collect set of termination transition constraints *)
(* based on the termination context of a function    *)
(*****************************************************)
let rec collect_term_trans_constrs_callee_term_spec utils ctx unk tspec =
	match tspec with
	| TBase b -> 
		let reach_ctx = join_conjunctions (ctx @ [unk.unk_trans_ctx] @ [b.term_base_cond]) in
		if (utils.is_sat reach_ctx) then
			let constr = {
				trans_src = Unknown unk;
				trans_dst = b.term_base_res; } in
			Hashtbl.add term_constr_tbl 
				(id_of_term_res constr.trans_src, id_of_term_res constr.trans_dst) constr;
			[constr]
		else []
	| TCase c -> List.concat (List.map (fun (cc, sc) ->
		collect_term_trans_constrs_callee_term_spec utils (ctx @ [cc]) unk sc) c)
	| TSeq _ -> []

let collect_term_trans_constrs_base_spec utils ctx unk =
	let callee_tspec = rename_term_spec unk.unk_params (look_up_term_spec unk.unk_callee) in
	collect_term_trans_constrs_callee_term_spec utils ctx unk callee_tspec

let rec collect_term_trans_constrs_term_spec utils ctx tspec =
	match tspec with
	| TBase b -> (match b.term_base_res with
		| Term _ | Loop _ -> []
		| Unknown unk -> collect_term_trans_constrs_base_spec utils (ctx @ [b.term_base_cond]) unk)
	| TCase c -> List.concat (List.map (fun (cc, sc) ->
		collect_term_trans_constrs_term_spec utils (ctx @ [cc]) sc) c)
	| TSeq s -> 
		(* We need to solve the FIRST UNKNOWN in the sequence first, *)
		(* by determine whether the BASE CASE is reachable or not    *)
		collect_term_trans_constrs_term_spec utils ctx s.term_seq_fst

let collect_term_trans_constrs_one_proc utils mn =
	let mn_tspec = look_up_term_spec mn in
	collect_term_trans_constrs_term_spec utils [] mn_tspec

(* let collect_term_trans_constraints_all_procs utils procs =                     *)
(* 	List.concat (List.map (collect_term_trans_constraints_one_proc utils) procs) *)
	
(*****************************************************)	 		
(*
let norm_src_cond sc =
	match sc with
	| BForm ((bf, _), _) -> (match bf with
		| Lt (e1, e2, pos)	-> mkSubtract e2 e1 pos                              (* e1<e2  --> e2-e1>0   *)
		| Lte (e1, e2, pos)	-> mkAdd (mkSubtract e2 e1 pos) (mkIConst 1 pos) pos (* e1<=e2 --> e2-e1+1>0 *)
		| Gt (e1, e2, pos)	-> mkSubtract e1 e2 pos                              (* e1>e2  --> e1-e2>0   *)
		| Gte (e1, e2, pos)	-> mkAdd (mkSubtract e1 e2 pos) (mkIConst 1 pos) pos (* e1>=e2 --> e1-e2+1>0 *)
		| Eq (e1, e2, pos)	-> mkAdd (mkSubtract e1 e2 pos) (mkIConst 1 pos) pos (* e1=e2  --> e1-e2+1>0 *)
		| _ -> report_error no_pos "Termination Inference: Unexpected case condition"
		)
	| _ -> report_error no_pos "Termination Inference: Unexpected case condition"

let norm_dst_cond dc =
	match dc with
	| BForm ((bf, _), _) -> (match bf with
		| Lt (e1, e2, pos)	-> mkAdd (mkSubtract e1 e2 pos) (mkIConst 1 pos) pos (* e1<e2  --> e1-e2+1<=0 *)
		| Lte (e1, e2, pos)	-> mkSubtract e1 e2 pos                              (* e1<=e2 --> e1-e2<=0   *)
		| Gt (e1, e2, pos)	-> mkAdd (mkSubtract e2 e1 pos) (mkIConst 1 pos) pos (* e1>e2  --> e2-e1+1<=0 *)
		| Gte (e1, e2, pos)	-> mkSubtract e2 e1 pos                              (* e1>=e2 --> e2-e1<=0   *)
		| Eq (e1, e2, pos)	-> mkSubtract e1 e2 pos                              (* e1=e2  --> e1-e2=0    *)
		| _ -> report_error no_pos "Termination Inference: Unexpected case condition"
		)
	| _ -> report_error no_pos "Termination Inference: Unexpected case condition"

(*| ************************************************************ *)
(*| Solve termination constraints                                *)
(*| Step 1: Build a graph to present termination constraints     *)
(*| Step 2: Do inference bottom-up - Infer termination condition *)
(*| at transition A>>B where A!=B                                *)
(*| ************************************************************ *)

let simplify_inf_cond utils ivars inf_cond ctx =
	let inf_cond = CP.mkOr (mkNot ctx None no_pos) inf_cond None no_pos in
	let qvars = diff_svl (CP.fv inf_cond) ivars in
	let simpl_cond = utils.simplify (mkForall qvars inf_cond None no_pos) in
	let simpl_cl = CP.list_of_disjs simpl_cond in
	(* To remove the base case in the inferred condition *)
	(* Empty list means FALSE                            *)
	List.filter (fun c -> utils.is_sat (CP.mkAnd c ctx no_pos)) simpl_cl
	(* [simpl_cond] *)
	
(* Fixpoint Calculation for an exact termination *)
(* condition with Equality in Base Case          *)
(* Do NOT support mutually recursive calls       *)
let term_cond_by_fixcalc utils subst base ctx =
	let args, params = subst in
	let cnt = SpecVar (Int, "cnt", Unprimed) in
	let fcnt = "fcnt" in
	let base_cnt = mkAnd base (mkEqVarInt cnt 0 no_pos) no_pos in (* base && cnt=0 *)
	let rec_cnt = 
		let cnt1 = SpecVar (Int, "cnt1", Unprimed) in
		let cnt_dec = mkPure (mkEq (mkVar cnt1 no_pos) 
			(mkSubtract (mkVar cnt no_pos) (mkIConst 1 no_pos) no_pos) no_pos) in (* cnt1=cnt-1 *)
		let qvars = (diff_svl (CP.fv ctx) args) @ [cnt1] in
		let rel = mkPure (mkRelForm fcnt (List.map (fun v -> mkVar v no_pos) (params @ [cnt1])) no_pos) in
		CP.mkExists qvars (mkAnd ctx (mkAnd cnt_dec rel no_pos) no_pos) None no_pos
	in
	let fml = CP.mkOr base_cnt rec_cnt None no_pos in
	let res = utils.fixcalc fcnt (args @ [cnt]) [] fml in
	let qres = List.map (fun f -> mkExists_with_simpl utils.simplify [cnt] f None no_pos) res in
	qres
	
(* Check the condition for a monotone decreasing sequence start       *)
(* from the condition Phi(X)>=0 and the update function X'=f(X)       *)
(* If failed, find the condition for a monotone increasing sequence   *)
(* base_cond: Condition for base case reachability (in one execution) *)
let check_monotone_decreasing_sequence utils ivars subst f_seq base_cond f_upd =
	let x = fst subst in
	let xp = snd subst in
	let xpp = List.map (fun x -> match x with
	| SpecVar (typ, name, prim) -> SpecVar (typ, fresh_old_name name, prim)) xp in
	let s_0 = f_seq in (* Phi(X) *)
	let s_1 = e_apply_subs (List.combine x xp) s_0 in (* Phi(X') - subst: X -> X' *)
	let s_2 = e_apply_subs (List.combine xp xpp) s_1 in (* Phi(X'') - subst: X' -> X'' *)
	let f_upd_p = CP.subst_avoid_capture x xp (CP.subst_avoid_capture xp xpp f_upd) in
	
	(* If true |- s_0 > s_1 Then return True                      *)
	(* Else If s_0 > s_1 |- s_1 > s_2 Then return (s_0 - s_1 > 0) *)
	(* Else return (s_1 <= 0)                                     *)
	let nonterm_cond, term_cond, rank = 
	begin
		if (utils.imply f_upd base_cond) then
			(* CASE 0: 1-step execution *) 
			([], [CP.mkTrue no_pos], None)
		else
			(* Condition for decreasing sequence *)
			let dec_cond = mkPure (mkGt s_0 s_1 no_pos) in 
			if (utils.imply f_upd dec_cond) then
				(* CASE 1: The sequence ALWAYS decreasing *)
				(* Fixpoint calculator is used to calculate the  *)
				(* exact condition if base condition is equality *)
				let r = if (is_eq_exp base_cond) then 
					term_cond_by_fixcalc utils subst (CP.subst_avoid_capture xp x base_cond) f_upd
					else [CP.mkTrue no_pos]
				in ([], r, Some s_0)
			(* CASE 2: The sequence ALWAYS increasing *)
			(* We do not need to check this case, because it has *)
			(* already been done by the reachability check       *)
			else begin
				(* CASE 3: Otherwise, the sequence MAY or MAY NOT decreasing, *)
				(* based on some conditions that need to be inferred          *)
				let mkExists vs f = CP.mkExists vs f None no_pos in
				let mkAnd f1 f2 = mkAnd f1 f2 no_pos in  
				let compose_ctx = mkAnd 
					(mkExists (diff_svl (CP.fv f_upd) (x @ xp)) f_upd)
					(mkExists (diff_svl (CP.fv f_upd_p) (xp @ xpp)) f_upd_p)
				in
				(* CASE 3-1 *)
				let is_dec, term_cond, rank =
					let test = utils.imply (mkAnd compose_ctx dec_cond) (mkPure (mkGt s_1 s_2 no_pos)) in
					if test then
						(* The sequence can be proved monotone strictly decreasing with dec_cond *)
						(* In this case, sometimes the condition for equality base case *)
						(* is NON-LINEAR, that cannot be handled by Fixcalc             *)
						let rl = simplify_inf_cond utils ivars dec_cond f_upd in
						let rl = List.filter (fun r -> utils.is_sat 
							(mkAnd r (mkPure (mkGt f_seq (mkIConst 0 no_pos) no_pos)))) rl in
						(test, rl, Some s_0)
					else (test, [], None)
				in
				let inc_cond = mkPure (mkLte s_0 s_1 no_pos) in
				(* CASE 3-2 *)
				let is_inc, nonterm_cond =
					let test = utils.imply (mkAnd compose_ctx inc_cond) (mkPure (mkLte s_1 s_2 no_pos)) in
					(* The sequence is monotone increasing --> Non-termination *)
					if test then 
						let rl = simplify_inf_cond utils ivars inc_cond f_upd in
						let rl = List.filter (fun r -> utils.is_sat 
							(mkAnd r (mkPure (mkGt f_seq (mkIConst 0 no_pos) no_pos)))) rl in
						(test, rl)
					else (test, [])
				in
				if (is_dec || is_inc) then nonterm_cond, term_cond, rank
				(* The sequence is neither monotone increasing nor monotone decreasing, *)
				(* so that the function returns the condition for one-step execution    *)
				else ([], simplify_inf_cond utils ivars base_cond f_upd, None)
			end
	end in
	(* Debugging Information *)
	begin
		info_pprint ">>>>>>> check_monotone_decreasing_sequence <<<<<<<";
		info_hprint "s0" !print_pure_exp s_0;
		info_hprint "s1" !print_pure_exp s_1;
		info_hprint "s2" !print_pure_exp s_2;
		info_hprint "ctx s0->s1" !print_pure_formula f_upd;
		info_hprint "ctx s1->s2" !print_pure_formula f_upd_p;
		info_hprint "Infer NonTerm Cond" (pr_list !print_pure_formula) nonterm_cond;
		info_hprint "Infer Term Cond" (pr_list !print_pure_formula) term_cond;
		info_hprint "Infer Rank" (pr_option !print_pure_exp) rank;
		info_pprint "\n";
	end; 
	(nonterm_cond, term_cond, rank)

(* ivars is the set of variables that the inferred condition is based on them *)
let infer_term_condition utils ivars tc (* trans_constraint *) =
	let sc = List.nth tc.trans_src_cond ((List.length tc.trans_src_cond) - 1) in
	let dc = List.nth tc.trans_dst_cond ((List.length tc.trans_dst_cond) - 1) in
	(* TODO: Support conjunctions in the condition *)
	(* Disjunctions have already been split        *)
	let sce = norm_src_cond sc in (* A in A>0  *)
	let dce = norm_dst_cond dc in (* B in B<=0 *)
	check_monotone_decreasing_sequence utils ivars tc.trans_subst sce dc tc.trans_ctx 
*)
(* Build the graph of reachability *)	
module TNode = struct
	type t = term_res
	let compare = compare
	let hash = Hashtbl.hash
	let equal = (=)
end

module TG = Graph.Persistent.Digraph.Concrete(TNode)		
module TGC = Graph.Components.Make(TG)	
module TGN = Graph.Oper.Neighbourhood(TG)

(* Build a reachability graph from set of termination constraints *)
let rec graph_of_term_constrs t_constrs =
	let tg = TG.empty in
	let tg = List.fold_left (fun g constr ->
		TG.add_vertex g constr.trans_src;
		TG.add_vertex g constr.trans_dst;
		TG.add_edge g constr.trans_src constr.trans_dst) tg t_constrs
	in tg 

and is_neighbors_of_scc (src: TG.V.t list) (dst: TG.V.t list) tg : bool =
	let neighbors = List.filter (fun m -> not (List.mem m src)) (TGN.list_from_vertices tg src) in
	List.exists (fun v -> List.mem v neighbors) dst
	
(* Find a set of neighbor scc groups of a scc *)		
and neighbors_of_scc (scc: TG.V.t list) (scc_list: TG.V.t list list) tg : TG.V.t list list =
	let neighbors = List.filter (fun m -> not (List.mem m scc)) (TGN.list_from_vertices tg scc) in
	(* let scc_neighbors = List.find_all (fun s -> is_neighbors_of_scc scc s) scc_list in *) (* Less efficient *)
	let scc_neighbors = List.find_all (fun s -> List.exists (fun m -> List.mem m neighbors) s) scc_list in 
	scc_neighbors

(* Find ALL sccs that can reach from src *)
and reachable_sccs_top_down (src: TG.V.t list) (scc_list: TG.V.t list list) tg = 
	let v_neighbors = List.filter (fun m -> not (List.mem m src)) (TGN.list_from_vertices tg src) in
	let scc_neighbors, others = List.partition (fun s -> List.exists (fun v -> List.mem v v_neighbors) s) scc_list in
	List.fold_left (fun (res, rem) s ->
		let s_reachable_sccs, rem = reachable_sccs_top_down s rem tg in
		(res @ s_reachable_sccs, rem)) (scc_neighbors, others) scc_neighbors

and reachable_sccs_bottom_up (src: TG.V.t list) (scc_list: TG.V.t list list) tg = 
	let preds = List.concat (List.map (TG.pred tg) src) in 
	let scc_preds, others = List.partition (fun s -> List.exists (fun v -> List.mem v preds) s) scc_list in
	List.fold_left (fun (res, rem) s ->
		let s_pred_sccs, rem = reachable_sccs_bottom_up s rem tg in
		(res @ s_pred_sccs, rem)) (scc_preds, others) scc_preds

(* Partition a list of sccs into groups of reachable sccs *)
and partition_scc_list reachable_sccs (scc_list: TG.V.t list list) tg = 
	if scc_list = [] then []
	else
		let root = List.hd scc_list in
		let rem = List.tl scc_list in
		let root_reachable_sccs, rem = reachable_sccs root rem tg in
		(root::root_reachable_sccs)::(partition_scc_list reachable_sccs rem tg)
		
and scc_sort (scc_list: TG.V.t list list) tg : TG.V.t list list =
  let compare_scc scc1 scc2 =
		if (List.mem scc2 (neighbors_of_scc scc1 scc_list tg)) then -1 (* scc1 -> scc2 => [scc2, scc1] *)
		else if (List.mem scc1 (neighbors_of_scc scc2 scc_list tg)) then 1 (* scc2 -> scc1 *)
		else 0
  in List.fast_sort (fun s1 s2 -> compare_scc s1 s2) scc_list 
	
(* Check whether a scc group can reach Term or Loop or not *)	
and is_may_term_reachable (scc_group: TG.V.t list list) =
	List.exists (fun v -> match v with
	| Term _ -> true | _ -> false) (List.concat scc_group)

(****************************************)
(** DRIVER FOR SOLVING CONSTRS PROCESS **)	
(****************************************)
let solve_constrs constrs =
	let tg = graph_of_term_constrs constrs in
	let scc_list = scc_sort (TGC.scc_list tg) tg in
	let scc_groups = partition_scc_list reachable_sccs_bottom_up (List.rev scc_list) tg in
	let may_term, must_loop = List.partition (fun sg -> is_may_term_reachable sg) scc_groups in
	print_endline (pr_list (pr_list !print_term_res) scc_list);
	print_endline (pr_list (pr_list (pr_list !print_term_res)) scc_groups);
	print_endline (pr_list (pr_list (pr_list !print_term_res)) must_loop);
	print_endline (pr_list (pr_list (pr_list !print_term_res)) may_term)

(***************** MAIN *****************)									
let main utils procs =
	List.iter (fun proc ->
		let mn = proc.proc_name in
		let _ = print_endline ("Termination Inference for " ^ mn) in
		(* let t_ctx = look_up_term_ctx mn in *)
		(* let _ = info_hprint "Termination Context" (pr_list !print_term_ctx) t_ctx in *)
		let t_spec = look_up_term_spec mn in 
		let t_constraints = collect_term_trans_constrs_one_proc utils mn in
		(* let t_constraints = [] in                                                    *)
		(* let args = get_method_args proc in                                           *)
		(* let inf_conds = List.fold_left (fun a c ->                                   *)
		(* 	(* if (c.trans_src != c.trans_dst) then *)                                  *)
		(* 	match c.trans_dst with                                                      *)
		(* 	| Term _ -> a @ [(infer_term_condition utils args c)]                       *)
		(* 	| _ -> a) [] t_constraints                                                  *)
		(* in                                                                           *)
		info_hprint "Termination Constraints"
			(pr_list (fun c -> "\n" ^ (!print_term_trans_constraint c))) t_constraints;
		info_pprint "\n";
		solve_constrs t_constraints;
		info_hprint "Termination Spec" !print_term_spec t_spec;
		info_pprint "\n"; 
	) procs



