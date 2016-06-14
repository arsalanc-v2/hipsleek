#include "xdebug.cppo"
open VarGen

open Globals
open Gen.Basic
open Printf
open Gen.BList

module F = Iformula
module P = Ipure_D
module CF = Cformula
module CP = Cpure
module MCP = Mcpure

type transmission = Send | Receive

let string_of_seq  = ";;"
let string_of_transmission t =
  match t with
  | Send    -> "!"
  | Receive -> "?"

let chan_id:  string option ref = ref None
let seq_id :  string option ref = ref None 
let trans_id: string option ref = ref None
let sess_id:  string option ref = ref None
let send_id:  string option ref = ref None
let recv_id:  string option ref = ref None
let sor_id:   string option ref = ref None

let set_prim_pred_id kind id = match kind with
    | Transmission -> trans_id := Some id
    | Session      -> sess_id := Some id
    | Channel      -> chan_id := Some id
    | Send         -> send_id := Some id
    | Receive      -> recv_id := Some id
    | Sequence     -> seq_id := Some id
    | SOr          -> sor_id := Some id

let get_prim_pred_id pred_ref =
  match !pred_ref with
    | Some str -> str
    | None -> ""

(* ======= base formula for session type ====== *)
(* ============================================ *)
module type Message_type = sig
  type formula
  type pure_formula
  type h_formula
  type ho_param_formula
  type node
  type param
  type arg = node * ident * (ho_param_formula list) *
             (param list) * VarGen.loc

  val is_emp : formula -> bool
  val print  : formula -> string
  val mk_node: arg -> h_formula
  val mk_formula_heap_only:  h_formula -> VarGen.loc -> formula
  val mk_rflow_formula:  formula -> ?kind:ho_flow_kind -> ho_param_formula
  val mk_rflow_formula_from_heap:  h_formula -> ?kind:ho_flow_kind -> VarGen.loc -> ho_param_formula
  val mk_formula: pure_formula -> arg -> formula
  val mk_star: h_formula -> h_formula -> VarGen.loc -> h_formula
  val mk_or: formula -> formula -> VarGen.loc -> formula
  val mk_empty: unit -> h_formula
  val choose_ptr: ?ptr:string -> unit -> node
  val set_param:  ident ->  VarGen.loc -> param
end;;

module IForm = struct
  type formula = F.formula
  type pure_formula = P.formula
  type h_formula = F.h_formula
  type ho_param_formula = F.rflow_formula
  type node = Globals.ident * VarGen.primed
  type param = Ipure.exp
  type arg = node * ident * (ho_param_formula list) *
             (param list) * VarGen.loc

  let is_emp f = failwith x_tbi
  let print    = !F.print_formula
  (* ptr - pointer to heap, 
     name - name of heap struct
     ho - HO param 
  *)
  let mk_node (ptr, name, ho, params, pos)  =
    let h = (F.mkHeapNode ptr name ho 0 false (*dr*) SPLIT0
               (P.ConstAnn(Mutable)) false false false None params [] None pos) in
    h

  let mk_formula_heap_only h pos =
    (* let h = mk_node (ptr, name, ho, params, pos) in *)
    F.formula_of_heap_1 h pos

  let mk_rflow_formula f ?kind:(k=NEUTRAL) =
    {  F.rflow_kind = k;
       F.rflow_base = f;
    }

  let mk_rflow_formula_from_heap h ?kind:(k=NEUTRAL) pos =
    let f =  mk_formula_heap_only h pos in
    {  F.rflow_kind = k;
       F.rflow_base = f;
    }

  let mk_formula pure (ptr, name, ho, params, pos)  =
    let h = mk_node (ptr, name, ho, params, pos) in
    F.mkBase_wo_flow h pure [] pos

  let mk_star h1 h2 pos =
    F.mkStar h1 h2 pos

  let choose_ptr ?ptr:(str="self") () =
    (str,Unprimed)

  let mk_or f1 f2 pos =
    F.mkOr f1 f2 pos

  let mk_empty () = F.HEmp

  let set_param id pos = Ipure_D.Var((id,Unprimed), pos) 

end;;

module CForm = struct
  type formula = CF.formula
  type pure_formula = CP.formula
  type h_formula = CF.h_formula
  type ho_param_formula = CF.rflow_formula
  type node = CP.spec_var
  type param = CP.spec_var
  type arg = node * ident * (ho_param_formula list) *
             (param list) * VarGen.loc

  let is_emp f = failwith x_tbi
  let print    = !CF.print_formula
  let mk_node (ptr, name, ho, params, pos) =
    let h = CF.mkViewNode ptr name params pos in
    match h with
      | CF.ViewNode node -> CF.ViewNode {node with h_formula_view_ho_arguments = ho}
      | _ -> failwith "Not a ViewNode."

  let mk_formula_heap_only h pos =
    CF.formula_of_heap h pos

  let mk_rflow_formula f ?kind:(k=NEUTRAL) =
    { CF.rflow_kind = k;
      CF.rflow_base = f;
    }

  let mk_rflow_formula_from_heap h ?kind:(k=NEUTRAL) pos =
    let f = mk_formula_heap_only h pos in
    { CF.rflow_kind = k;
      CF.rflow_base = f;
    }

  let mk_formula pure (ptr, name, ho, params, pos) =
    let h = mk_node (ptr, name, ho, params, pos) in
    let mix_formula = MCP.OnePF pure in
    CF.mkBase_simp h mix_formula

  let mk_star h1 h2 pos =
    CF.mkStarH h1 h2 pos

  let choose_ptr ?ptr:(str="self") () =
    CP.SpecVar(UNK,str,Unprimed)

  let mk_or f1 f2 pos =
    CF.mkOr f1 f2 pos

  let mk_empty () = CF.HEmp

  let set_param id pos = CP.SpecVar(UNK,id,Unprimed)

end;;

(* inst for iformula & cformula *)
module Protocol_base_formula =
  functor  (Msg: Message_type) ->
  struct
    include Msg
    type t = Msg.formula
    type a = ident * ident * VarGen.loc
    type base = {
      protocol_base_formula_sender   : ident;
      protocol_base_formula_receiver : ident;
      protocol_base_formula_message  : t;
      protocol_base_formula_pos      : VarGen.loc;
    }

    let print_message f = Msg.print f.protocol_base_formula_message

    let print_session_base f = begin
      Printf.printf "%s -> %s : " f.protocol_base_formula_sender f.protocol_base_formula_receiver;
      Printf.printf "%s" (print_message f);
    end

    let mk_base (sender, receiver, pos) formula = {
      protocol_base_formula_sender    = sender;
      protocol_base_formula_receiver  = receiver;
      protocol_base_formula_message   = formula;
      protocol_base_formula_pos       = pos;
    }

    let trans_base base =
      let ptr = Msg.choose_ptr ~ptr:session_msg_id () in
      let name = get_prim_pred_id trans_id in
      let args = [Msg.mk_rflow_formula base.protocol_base_formula_message ~kind:NEUTRAL] in
      let params = [base.protocol_base_formula_sender; base.protocol_base_formula_receiver] in
      let params = List.map (fun a -> Msg.set_param a base.protocol_base_formula_pos) params in
      Msg.mk_node (ptr, name, args, params, base.protocol_base_formula_pos)

  end;;

(* inst for iformula & cformula *)
module Projection_base_formula =
  functor  (Msg: Message_type) ->
  struct
    include Msg
    type t = Msg.formula
    type a = transmission * ident * VarGen.loc
    type base = {
      projection_base_formula_op      : transmission;
      projection_base_formula_channel : ident;
      projection_base_formula_message : t;
      projection_base_formula_pos     : VarGen.loc;
    }

    let print_message f = Msg.print f.projection_base_formula_message

    let print_session_base f =
      Printf.printf "%s%s(%s)"
        f.projection_base_formula_channel
        (string_of_transmission f.projection_base_formula_op )
        (print_message f)

    let mk_base (transmission, channel, pos) formula = {
      projection_base_formula_op      = transmission;
      projection_base_formula_channel = channel;
      projection_base_formula_message = formula;
      projection_base_formula_pos     = pos;
    }

    let trans_base base =
      let ptr = Msg.choose_ptr ~ptr:base.projection_base_formula_channel () in
      let name = match base.projection_base_formula_op with
                   | Send -> get_prim_pred_id send_id
                   | Receive -> get_prim_pred_id recv_id in
      let args = match base.projection_base_formula_op with
                   | Send -> [Msg.mk_rflow_formula base.projection_base_formula_message ~kind:OUTFLOW]
                   | Receive -> [Msg.mk_rflow_formula base.projection_base_formula_message ~kind:INFLOW] in
      let params = [] in
      Msg.mk_node (ptr, name, args, params, base.projection_base_formula_pos)

  end;;

module type Session_base =
sig
  include Message_type
  type t
  type a
  type base

  val print_session_base : base -> unit
  val mk_base : a -> t -> base
  val trans_base : base -> h_formula
end;;

(* ============== session type ================ *)
(* ============================================ *)
module Make_Session (Base: Session_base) = struct
  type t = Base.base
  
  type session =
    | SSeq  of session_seq_formula
    | SOr   of session_or_formula
    | SStar of session_star_formula
    | SBase of t
    | SEmp

  and session_seq_formula = {
    session_seq_formula_head: session;
    session_seq_formula_tail: session;
    session_seq_formula_pos:  loc;
  }

  and session_or_formula = {
    session_seq_formula_or1: session;
    session_seq_formula_or2: session;
    session_seq_formula_pos:  loc;
  }

  and session_star_formula = {
    session_seq_formula_star1: session;
    session_seq_formula_star2: session;
    session_seq_formula_pos:  loc;
  }

  let rec print_session s = begin
          print_one_session s;
          print_newline ();
  end

  and print_one_session s = match s with
    | SSeq s  -> print_session_seq s
    | SOr s   -> print_session_or s
    | SStar s -> print_session_star s
    | SBase s -> print_session_base s
    | SEmp    -> print_session_emp ()

  and print_session_base = Base.print_session_base

  and print_session_emp () = print_string "emp"
  
  and print_session_seq s = begin
          Printf.printf "(";
          print_one_session s.session_seq_formula_head;
          Printf.printf ") %s (" string_of_seq;
          print_one_session s.session_seq_formula_tail;
          Printf.printf ")";
  end

  and print_session_or s = begin
          Printf.printf "(";
          print_one_session s.session_seq_formula_or1;
          Printf.printf ") %s (" "or";
          print_one_session s.session_seq_formula_or2;
          Printf.printf ")";
  end

  and print_session_star s = begin
          Printf.printf "(";
          print_one_session s.session_seq_formula_star1;
          Printf.printf ") %s (" "*";
          print_one_session s.session_seq_formula_star2;
          Printf.printf ")";
  end

  let mk_base a b = SBase (Base.mk_base a b)

  and mk_session_seq_formula session1 session2 loc = SSeq {
      session_seq_formula_head = session1;
      session_seq_formula_tail = session2;
      session_seq_formula_pos  = loc;
    }

  and mk_session_or_formula session1 session2 loc = SOr {
    session_seq_formula_or1 = session1;
    session_seq_formula_or2 = session2;
    session_seq_formula_pos = loc;
    }

  and mk_session_star_formula session1 session2 loc = SStar {
    session_seq_formula_star1 = session1;
    session_seq_formula_star2 = session2;
    session_seq_formula_pos   = loc;
    }

  let mk_seq_node args params pos  =
    let arg1 = Base.choose_ptr () in (* decide which name should be given here *)
    let name = Gen.map_opt_def (failwith "SESSION: op id not set") idf !seq_id in
    let args = List.map (fun a -> Base.mk_rflow_formula_from_heap a pos) args in
    let params = List.map (fun a -> Base.set_param a pos) params in
    (* let a = (sv, name, args, params, pos) in *)
    Base.mk_node (arg1, name, args, params, pos)
    (* failwith x_tbi *)

  and mk_star_node h1 h2 pos =
    Base.mk_star h1 h2 pos

  and mk_or_node h1 h2 pos =
    let f1 = Base.mk_formula_heap_only h1 pos in
    let f2 = Base.mk_formula_heap_only h2 pos in
    let or_node = Base.mk_or f1 f2 pos in
    (* why doesn't it work without ~kind, which is optional? *)
    let rflow_form = (Base.mk_rflow_formula or_node ~kind:NEUTRAL) in
    let ptr = Base.choose_ptr () in
    let name =  match !sor_id with
                  | Some str -> str
                  | None -> "" in
    let args = [rflow_form] in
    let params = [] in
    Base.mk_node (ptr, name, args, params, pos)

  let rec trans_from_session s =
    match s with
    | SSeq s  ->
        let arg1 = trans_from_session s.session_seq_formula_head in
        let arg2 = trans_from_session s.session_seq_formula_tail in
        mk_seq_node [arg1;arg2] [] s.session_seq_formula_pos
      (* (\* node, view-name, ho-args, args *\) *)
      (* Base.mkFNode sv !seq_id [arg1;arg2] []
      failwith x_tbi *)
    | SOr s   ->
        let arg1 = trans_from_session s.session_seq_formula_or1 in
        let arg2 = trans_from_session s.session_seq_formula_or2 in
        mk_or_node arg1 arg2 s.session_seq_formula_pos
    | SStar s ->
        let arg1 = trans_from_session s.session_seq_formula_star1 in
        let arg2 = trans_from_session s.session_seq_formula_star2 in
        mk_star_node arg1 arg2 s.session_seq_formula_pos
    | SBase s -> Base.trans_base s
    | SEmp    -> Base.mk_empty ()

end;;

(* =========== Protocol / Projection ========== *)
(* ============================================ *)

module IProtocol_base = Protocol_base_formula(IForm) ;;
module CProtocol_base = Protocol_base_formula(CForm) ;;
module IProjection_base = Projection_base_formula(IForm) ;;
module CProjection_base = Projection_base_formula(CForm) ;;

module IProtocol = Make_Session(IProtocol_base);;
module CProtocol = Make_Session(CProtocol_base);;

module IProjection = Make_Session(IProjection_base);;
module CProjection = Make_Session(CProjection_base);;

type session_type = ProtocolSession of IProtocol.session
                  | ProjectionSession of IProjection.session

(* =========== Make Methods ========== *)
(* ============================================ *)


let boo () =
  let prot = IProtocol.mk_base ("", "", no_pos) (F.mkTrue_nf no_pos) in
  IProtocol.print_session prot
  ;;