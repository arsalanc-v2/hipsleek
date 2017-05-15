#include "xdebug.cppo"
open VarGen

open Globals
open Gen.Basic
open Printf
open Gen.BList

module CP = Cpure
module SProt  = Session.IProtocol
module SBProt = Session.IProtocol_base
module SIOrd = Session.IOrders

type role = SIOrd.role
type chan = SIOrd.chan
type suid = SIOrd.suid
              
(* elements of the boundaries *)
type 'a bform = BBase of 'a | BStar of ('a bform) * ('a bform)
and  'a eform = BOT | FBase of 'a bform | BOr of ('a eform) * ('a eform)

(* boundary base element *)
type event = SIOrd.event

(* boundary base element *)
and transmission = SIOrd.transmission

(* ------------------------------ *)
(* --- boundary base elements --- *)
module type BOUNDARY_BASE_ELEMENT_TYPE =
sig
  type t
  type a

  val make : a -> t
  val eq : t -> t -> bool
  val string_of : t -> string
end;;

module BEvent =
struct
  type t = event
  type a = role * suid * chan
           
  let make ((role,uid,chan) : a) : t = {role = role; uid = uid; channel = chan }
                                         
  let eq (e1:t) (e2:t) : bool =
    (SBProt.eq_suid e1.uid e2.uid) && (SBProt.eq_role e1.role e2.role)

  let string_of (e:t) : string = (SBProt.string_of_role e.role) ^ "^" ^(SBProt.string_of_suid e.uid)

end;;

module BTrans =
struct
  type t = transmission
  type a = role * role * chan * suid
           
  let make ((sender,receiver,chan,uid) :a) : t =
    {sender = sender; receiver = receiver; channel = chan; uid = uid}
    
  let eq (t1:t) (t2:t) : bool =
    (SBProt.eq_suid t1.uid t2.uid)
    && (SBProt.eq_role t1.sender t2.sender)
    && (SBProt.eq_role t1.receiver t2.receiver)
    && (SBProt.eq_chan t1.channel t2.channel)
       
  let string_of (e:t) : string =
    (SBProt.string_of_role e.sender) ^ "-" ^ (SBProt.string_of_suid e.uid) ^ "->" ^ (SBProt.string_of_role e.receiver)

  let get_sender (trans:t)   =  trans.sender
  let get_receiver (trans:t) =  trans.receiver
  let get_suid (trans:t)     =  trans.uid
  let get_chan (trans:t)     =  trans.channel

end;;

(* ------------------------------ *)
(* ------ boundary elements ----- *)

module type BOUNDARY_ELEMENT_TYPE =
sig
  (* include BOUNDARY_BASE_ELEMENT_TYPE *)
  type t
  type base
  val bot :       unit -> t
  val is_bot :    t -> bool
  val string_of : t -> string
  val eq :        t -> t -> bool
  val mk_base :   base -> t
  val mk_or :     t -> t -> t
  val mk_star :   t -> t -> t
  val merge_seq  : t -> t -> t
  val merge_sor  : t -> t -> t
  val merge_star : t -> t -> t
  val add_elem   : t ->t -> t
end;;

module BOUNDARY_ELEMENT =
  functor (Base: BOUNDARY_BASE_ELEMENT_TYPE) ->
  struct
    type base = Base.t
    type t = base eform
    let bot () = BOT
    let is_bot x =
      match x with
      | BOT -> true
      | _   -> false
    let eq e1 e2  = failwith x_tbi
    let rec string_of e = match e with
      | BOT -> "BOT"
      | FBase (BBase bs) -> Base.string_of bs
      | FBase (BStar (bs1,bs2)) -> (string_of (FBase bs1)) ^ "*" ^ (string_of (FBase bs2))
      | BOr (bs1,bs2) -> (string_of bs1) ^ "*" ^ (string_of bs2)
    let mk_base (base: base) : t = FBase (BBase base)
    let mk_or   (or1:t) (or2:t) : t = BOr (or1,or2)
    let mk_star (star1:t) (star2:t) : t =
      match star1, star2 with
      | FBase f1, FBase f2 ->  FBase (BStar (f1,f2))
      | _, _ -> failwith "BStar only between base elements"
    let merge_seq (f1:t) (f2:t) : t  = if (is_bot f1) then f2 else f1
    let merge_sor (f1:t) (f2:t) : t  = mk_or f1 f2
    let merge_star (f1:t) (f2:t) : t = if (is_bot f1) then f2
      else if (is_bot f2) then f1 else mk_star f1 f2
    let add_elem (old_e:t)(new_e:t) :t  = new_e
  end;;

module Orders_list  =
struct
  type t = SIOrd.assrt list
  type base = SIOrd.assrt

  let bot () = []
  let is_bot x = List.length x == 0
  let eq e1 e2 = failwith x_tbi
  let string_of e1 = (pr_list (SIOrd.string_of)) e1
  let mk_base (base: base) : t = failwith x_tbi
  let mk_or   (or1:t) (or2:t) : t = failwith x_tbi 
  let mk_star (star1:t) (star2:t) : t = failwith x_tbi 
  let merge_seq (f1:t) (f2:t) : t = failwith x_tbi
  let merge_sor (f1:t) (f2:t) : t = failwith x_tbi
  let merge_star (f1:t) (f2:t) : t = failwith x_tbi
  let mkSingleton (e:base) : t = [e]
  let add_elem (old_e:t) (new_e:t) :t  = old_e@new_e    
end;;

(* ------------------------------------------------ *)
(* singnature of the keys for the backtier/frontier *)
module type KEY_EQ_TYPE =
sig
  type t
  val eq : t -> t -> bool
  val string_of : t -> string   
end;;

(* key for RMap *)
module IRole =
struct
  type t = role
  let eq = SBProt.eq_role
  let string_of = SBProt.string_of_role
end;;

(* key for CMap *)
module IChan =
struct
  type t = chan
  let eq = SBProt.eq_chan
  let string_of = SBProt.string_of_chan
end;;

(* key for CMap *)
module UID =
struct
  type t = suid
  let eq = SBProt.eq_suid
  let string_of = SBProt.string_of_suid
end;;

(* ------------------------------------------------ *)
module type SMap_type =
sig

  type key
  type elem
  type emap
  type epart
  type elist
  type klist

  val eq: key -> key -> bool

  val string_of_elem : elem -> string
  val string_of_key  : key -> string

  val string_of:  emap -> string
    
  val mkEmpty : emap
  val is_empty :emap -> bool

  val mkSingleton : key -> elem -> emap
  val init : (key * elem) list -> emap
    
  val add : emap-> key -> elem -> emap
  val find : emap -> key -> elem
  val get_keys : emap -> klist

  val update_elem    : emap -> key -> elem -> emap
  val add_elem_dupl  : emap -> key -> elem -> emap
  val add_elem       : emap -> key -> elem -> emap
  
  val union      : emap -> emap -> emap
  val merge_seq  : emap -> emap -> emap
  val merge_sor  : emap -> emap -> emap
  val merge_star : emap -> emap -> emap 
  val map_data   : (elem -> elem) -> emap -> emap

end;;

module SMap
    (Key  : KEY_EQ_TYPE)
    (Elem : BOUNDARY_ELEMENT_TYPE) =
struct
  type key  = Key.t
  type elem = Elem.t
  type emap = (key * elem) list
  type epart = (elem list) list
  type elist = (elem list)
  type klist = (key list) 

  let eq = Key.eq 
  let string_of_elem = Elem.string_of
  let string_of_key  = Key.string_of 

  let string_of (e: emap) : string =    
    "["^ (pr_lst "\n" (pr_pair string_of_key string_of_elem) e) ^"]"
    
  let mkEmpty () : emap = []
  let is_empty (m:emap) = match m with | [] -> true | _ -> false

  let mkSingleton (key:key) (elem:elem) : emap = [(key,elem)]
  let init lst : emap = lst

  let find_aux (s: emap) (k:key) (d:elem) : elem =
    try
      snd(List.find (fun (k0,_) -> eq k0 k) s)
    with
      _ -> d

  (* find element with key k in s *)
  let find (s : emap) (k: key) : elem  = find_aux s k (Elem.bot ())

  let remove_duplicate_keys (keys:klist) : klist =
    let keys = List.fold_left (fun acc key ->
        if List.exists (eq key) acc then acc
        else (key::acc)) [] keys in
    keys

  (* each key is returned only once *)
  let get_keys (s : emap) : klist =
    let all_keys = List.map fst s in
    remove_duplicate_keys all_keys

  (* each key is returned only once *)
  let union_keys (e1:klist) (e2:klist) : klist =
    remove_duplicate_keys (e1@e2)

  let update_elem (e1:emap) (k:key) (el:elem) : emap =
    List.map (fun (k0,e0) -> if Key.eq k0 k then (k0, Elem.add_elem e0 el) else (k0,e0)) e1

  (* allow key duplicates *)
  let add_elem_dupl (e1:emap) (k:key) (el:elem) : emap =
    (k,el)::e1
    
  (* if key exists in emap, then replace its corresponding element *)
  let add_elem (e1:emap) (k:key) (el:elem) : emap =
    let update_f =  if (Elem.is_bot (find e1 k)) then add_elem_dupl else update_elem in
    update_f e1 k el

  (* this merge allows duplicates *)
  let union_dupl (e1:emap) (e2:emap) : emap =
    e1 @ e2

  (* TODO Andreea : debug below add/update_elem?*)
  (* this merge assumes e1 and e2 have no key duplicates *)
  let union (e1:emap) (e2:emap) : emap =
    List.fold_left (fun acc (key,elem) -> add_elem acc key elem) e1 e2

  let union (e1:emap) (e2:emap) : emap =
    let pr = string_of in
    Debug.no_2 "union" pr pr pr union e1 e2 
      
  (* this merge assumes e1 and e2 have no key duplicates *)
  let flatten (e0:emap list) : emap =    
    List.fold_left (fun acc e1 -> union acc e1) (mkEmpty ()) e0

  let flatten (e0:emap list) : emap =
    let pr = string_of in
    Debug.no_1 "flatten" (pr_list pr) pr flatten e0
  
  type op = SEQ | SOR | STAR

  (* generic merge emap function *)
  let merge_op op (e1:emap) (e2:emap) : emap =
    let merge_elem op =
      match op with
      | SEQ  -> Elem.merge_seq
      | SOR  -> Elem.merge_sor
      | STAR -> Elem.merge_star in
    List.fold_left (fun map (key,elem) ->
        let elem1 = find e1 key in (* \bot or some element *)
        let elem1 = (merge_elem op) elem1 elem in
        add_elem e1 key elem1) e1 e2 
    
  let merge_seq  (e1:emap) (e2:emap) :emap = merge_op SEQ e1 e2
      
  let merge_sor  (e1:emap) (e2:emap) :emap = merge_op SOR e1 e2
      
  let merge_star (e1:emap) (e2:emap) :emap = merge_op STAR e1 e2

  let map_data (fnc: elem->elem) (map: emap) : emap = List.map (fun (k,elem) -> (k, fnc elem)) map 

end;;

(* ------------------------------------------------ *)
module OL = Orders_list 
module Events = BOUNDARY_ELEMENT(BEvent) ;;
module Trans = BOUNDARY_ELEMENT(BTrans) ;;

module RMap = SMap(IRole)(Events) ;;
module CMap = SMap(IChan)(Trans) ;;
module ConstrMap = SMap(UID)(OL) ;;

(* ------------------------------------------------ *)
(* ------------- summary related stuff ------------ *)
type summary = {
  bborder : RMap.emap * CMap.emap;
  fborder : RMap.emap * CMap.emap;
  assumptions: ConstrMap.emap;
  guards     : ConstrMap.emap;
}

let mk_empty_summary () =
  let rmap     = RMap.mkEmpty () in
  let cmap     = CMap.mkEmpty () in
  let assum    = ConstrMap.mkEmpty () in
  let guards   = ConstrMap.mkEmpty () in
  {bborder = (rmap,cmap) ; fborder = (rmap,cmap) ; assumptions = assum ; guards = guards}

let init_summary bborder fborder assum guards = 
  {bborder = bborder ; fborder = fborder ; assumptions = assum ; guards = guards}

let string_of_border = pr_pair (add_str "RMap:" RMap.string_of) (add_str "CMap:" CMap.string_of)
  
  
(* ------------------------------------------------ *)
(* ----- merging functions for prot constructs ---- *)

module type ORDERS_TYPE =
sig
  type t
  val mk_hb : t -> t -> SIOrd.assrt
  val get_uid : t -> suid
end;;

module Orders_hbe =
struct
  type t = event
  let mk_hb = SIOrd.mk_hbe
  let get_uid (e:t) = e.uid
end;;

module Orders_hbt =
struct
  type t = transmission
  let mk_hb = SIOrd.mk_hbt
  let get_uid (e:t) = e.uid
end;;


module Merger
    (Ord  : ORDERS_TYPE) =
struct
  type t = Ord.t eform

  let rec merge (e1:t) (e2:t) : ConstrMap.emap =
    match e1,e2 with
    | FBase (BBase e1) , FBase (BBase e2) ->
      let elem = OL.mkSingleton (Ord.mk_hb e1 e2) in (* hbe hbi  *)
      let key  = Ord.get_uid e2 in
      ConstrMap.init [(key, elem)]
    | FBase (BStar (s1,s2)) , _ ->
      let new_e1 = merge (FBase s1) e2 in
      let new_e2 = merge (FBase s2) e2 in
      ConstrMap.union new_e1 new_e2       (* TODO: upgrade to no duplicates *)
    | _, FBase (BStar (s1,s2)) ->
      let new_e1 = merge e1 (FBase s1) in
      let new_e2 = merge e1 (FBase s2) in
      ConstrMap.union new_e1 new_e2       (* TODO: upgrade to no duplicates *)
    | BOr (s1,s2) , _ ->
      let new_e1 = merge s1 e2 in
      let new_e2 = merge s2 e2 in
      ConstrMap.union new_e1 new_e2       (* TODO: upgrade to no duplicates *)
    | _, BOr (s1,s2) ->
      let new_e1 = merge e1 s1 in
      let new_e2 = merge e1 s2 in
      ConstrMap.union new_e1 new_e2       (* TODO: upgrade to no duplicates *)
    | BOT, _
    | _, BOT -> ConstrMap.mkEmpty ()
end;;

module RMerger = Merger(Orders_hbe)
module CMerger = Merger(Orders_hbt)

let merge_set (b1:RMap.emap * CMap.emap) (b2:RMap.emap * CMap.emap) : ConstrMap.emap * ConstrMap.emap =
  let rmap1, cmap1 = b1 in
  let rmap2, cmap2 = b2 in
  let keys = RMap.union_keys (RMap.get_keys rmap1) (RMap.get_keys rmap2) in
  let () = y_ninfo_hp (add_str "keys" (pr_list IRole.string_of)) keys in
  let assumpt = List.map (fun key -> RMerger.merge (RMap.find rmap1 key) (RMap.find rmap2 key) )  keys in
  let assumpt = x_add_1 ConstrMap.flatten assumpt in
  let keys = CMap.union_keys (CMap.get_keys cmap1) (CMap.get_keys cmap2) in
  let guards = List.map (fun key -> CMerger.merge (CMap.find cmap1 key) (CMap.find cmap2 key) )  keys in
  let guards = x_add_1 ConstrMap.flatten guards in
  (* flatten guards and assumptions  *)
  (assumpt, guards)

(* generic border merge *)
let merge_border (b1:RMap.emap * CMap.emap) (b2:RMap.emap * CMap.emap)
    rmap_merge cmap_merge : RMap.emap * CMap.emap =
  let rmap1, cmap1 = b1 in
  let rmap2, cmap2 = b2 in
  let rmap0 = rmap_merge rmap1 rmap2 in 
  let cmap0 = cmap_merge cmap1 cmap2 in
  (rmap0,cmap0)

let merge_border (b1:RMap.emap * CMap.emap) (b2:RMap.emap * CMap.emap)
    rmap_merge cmap_merge : RMap.emap * CMap.emap =
  let pr = string_of_border in
  Debug.no_2 "merge_border" pr pr pr (fun _ _ -> merge_border b1 b2 rmap_merge cmap_merge) b1 b2

(* [;] in paper *)
let merge_seq_border (seq1:RMap.emap * CMap.emap) (seq2:RMap.emap * CMap.emap) : RMap.emap * CMap.emap =
  merge_border seq1 seq2 RMap.merge_seq CMap.merge_seq

(* [\/] in paper *)
let merge_sor_border (b1:RMap.emap * CMap.emap) (b2:RMap.emap * CMap.emap) : RMap.emap * CMap.emap =
  merge_border b1 b2 RMap.merge_sor CMap.merge_sor

(* [*] in paper *)
let merge_star_border (b1:RMap.emap * CMap.emap) (b2:RMap.emap * CMap.emap) : RMap.emap * CMap.emap =
  merge_border b1 b2 RMap.merge_star CMap.merge_star
  
(* f1 in paper *)
let merge_all_seq (seq1:summary) (seq2:summary) : summary =
  let bborder0 = merge_seq_border seq1.bborder seq2.bborder in
  let fborder0 = merge_seq_border seq2.fborder seq1.fborder in
  let assum3, guards3 = merge_set seq1.fborder seq2.bborder in
  let assume0 = x_add_1 ConstrMap.flatten [seq1.assumptions; seq2.assumptions; assum3] in
  let guards0 = x_add_1 ConstrMap.flatten [seq1.guards; seq2.guards; guards3] in
  init_summary bborder0 fborder0 assume0 guards0

let merge_all_sor (sor1:summary) (sor2:summary) : summary =
  let bborder0 = merge_sor_border sor1.bborder sor2.bborder in
  let fborder0 = merge_sor_border sor2.fborder sor1.fborder in
  let assume0 = ConstrMap.union sor1.assumptions sor2.assumptions in
  let guards0 = ConstrMap.union sor1.guards sor2.guards in
  init_summary bborder0 fborder0 assume0 guards0

let merge_all_star (star1:summary) (star2:summary) : summary =
  let bborder0 = merge_star_border star1.bborder star2.bborder in
  let fborder0 = merge_star_border star2.fborder star1.fborder in
  let assume0 = ConstrMap.union star1.assumptions star2.assumptions in
  let guards0 = ConstrMap.union star1.guards star2.guards in
  init_summary bborder0 fborder0 assume0 guards0

(* Normalize order assumptions and guards *)
(* Assume - normalizing transmission: S->R => (S) & (R) & (S <_CB R) *)
(* Guard - normalizing HB of transmission: A->B <_HB B->C => (A <_HB B) & (B <_HB C) *)
(* Everything else remains the same *)
let mk_order_normalization_x list =
    let helper assrt = match assrt with
      | SIOrd.Transm t -> 
        let event_sender = SIOrd.mk_assrt_event t.sender t.uid t.channel in
        let event_receiver = SIOrd.mk_assrt_event t.receiver t.uid t.channel in
        let create_cbe ev1 ev2 = match ev1, ev2 with
          | SIOrd.Event e1, SIOrd.Event e2 -> SIOrd.mk_cbe e1 e2
          | _,_ -> NoAssrt in
        let cbe = create_cbe event_sender event_receiver in
        [event_sender; event_receiver; cbe]
      | SIOrd.Order SIOrd.HBe _ 
      | SIOrd.Order SIOrd.CBe _ -> [assrt]
      | SIOrd.Order SIOrd.HBt hbt -> 
        let trans1 = hbt.hbt_transmission1 in
        let trans2 = hbt.hbt_transmission2 in
        let event1_sender = SIOrd.mk_assrt_event trans1.sender trans1.uid trans1.channel in
        let event1_receiver = SIOrd.mk_assrt_event trans1.receiver trans1.uid trans1.channel in
        let event2_sender = SIOrd.mk_assrt_event trans2.sender trans2.uid trans2.channel in
        let event2_receiver = SIOrd.mk_assrt_event trans2.receiver trans2.uid trans2.channel in
        let create_hbe ev1 ev2 = match ev1, ev2 with
          | SIOrd.Event e1, SIOrd.Event e2 -> SIOrd.mk_hbe e1 e2
          | _,_ -> SIOrd.NoAssrt in
        let hbe1 = create_hbe event1_sender event2_sender in
        let hbe2 = create_hbe event1_receiver event2_receiver in 
        [hbe1; hbe2]
      | _ -> []
     in
     let res = List.fold_left (fun acc assrt -> acc@(helper assrt)) [] list in
     res

let mk_order_normalization list = 
  let pr = pr_list SIOrd.string_of in 
  Debug.no_1 "OS.mk_order_normalization" pr pr mk_order_normalization_x list

let mk_and_list lst = 
  List.fold_left (fun acc assrt -> SIOrd.mk_and acc assrt) SIOrd.Bot lst 

let mk_and_list lst = 
  let pr = SIOrd.string_of in
  Debug.no_1 "OS.mk_and_list" (pr_list pr) pr mk_and_list lst

(* ------------------------------------------------ *)
(* Collects order assumptions and proof obligations.*)
(* The retuned result is a summary of the form:     *)
(* BackBorder x FrontBorder x Assumptions x Guards  *)
(*                                                  *)
(* where                                            *)
(*                                                  *)
(* Border: RMap x CMap                              *)
(* Assumptions : ConstrMap                          *)
(* Guards : ConstrMap                               *)
(* RMap :      role -> event                        *)
(* CMap :      chan -> transm                       *)
(* ConstrMap : uid  -> order                        *)

let rec collect prot =
  match prot with
  | SProt.SSeq  seq  -> merge_all_seq (collect seq.SProt.session_seq_formula_head)
                     (collect seq.SProt.session_seq_formula_tail)
  | SProt.SStar star -> merge_all_star (collect star.SProt.session_star_formula_star1)
                     (collect star.SProt.session_star_formula_star2)
  | SProt.SOr   sor  -> merge_all_sor (collect sor.SProt.session_sor_formula_or1)
                     (collect sor.SProt.session_sor_formula_or2)
  | SProt.SExists se -> collect se.SProt.session_exists_formula_session
  | SProt.SBase (Base tr) ->
    let sender   = tr.SBProt.protocol_base_formula_sender in
    let receiver = tr.SBProt.protocol_base_formula_receiver in
    let suid     = tr.SBProt.protocol_base_formula_uid in
    let fail str = failwith str in
    let chan     =
      match tr.SBProt.protocol_base_formula_chan with
      | None -> let () = y_binfo_pp "chan is none"  in failwith "expecting a specified channel"
      | Some chan -> chan in
      (* map_opt_def (fail "expecting a specified channel" ) *)
      (*   idf tr.SBProt.protocol_base_formula_chan in *)
    let event1   = BEvent.make (sender,suid,chan) in
    let event2   = BEvent.make (receiver,suid,chan) in
    let trans    = BTrans.make (sender,receiver,chan,suid) in
    (* INIT MAPS  *)
    let rmap     = RMap.init [(sender, Events.mk_base event1) ; (receiver, Events.mk_base event2)] in
    let cmap     = CMap.init [(chan, Trans.mk_base trans)] in
    let assum    = ConstrMap.init [(suid,OL.mkSingleton (SIOrd.Transm trans))] in
    let guards   = ConstrMap.mkEmpty () in
    {bborder = (rmap,cmap) ; fborder = (rmap,cmap) ; assumptions = assum ; guards = guards}
  | SProt.SEmp 
  | _ -> mk_empty_summary ()


(* creates a default summary wrt the view's parameters *)
let mk_def_summary roles channs =
  let roles  = List.map snd roles in
  let channs = List.map snd channs in
  let def_chan = SBProt.mk_chan (fresh_any_name "dummy") in
  let rmap =  List.map (fun role ->
      let fresh_suid = fresh_any_name role in
      let suid  = SBProt.mk_suid fresh_suid in
      let role  = SBProt.mk_role role in 
      let event = BEvent.make (role,suid,def_chan) in
      (role, Events.mk_base event)) roles in
  let cmap_int =  List.map (fun chan ->
      let fresh_suid = fresh_any_name chan in
      let suid     = SBProt.mk_suid fresh_suid in
      let sender   = SBProt.mk_role (fresh_any_name "S") in
      let receiver = SBProt.mk_role (fresh_any_name "R") in
      let chan     = SBProt.mk_chan chan in
      let trans    = BTrans.make (sender,receiver,chan,suid) in
      (chan, (* Trans.mk_base *) trans)) channs in
  let cmap = List.map (fun (c,t) -> (c, Trans.mk_base t)) cmap_int in 
  let assumes = List.map (fun (_,trans) ->
      let sender   = BTrans.get_sender trans in
      let receiver = BTrans.get_receiver trans in
      let suid     = BTrans.get_suid trans in
      let chan     = BTrans.get_chan trans in
      let ev1 = SIOrd.mk_event sender suid chan in
      let ev2 = SIOrd.mk_event receiver suid chan in
      let cb  = SIOrd.mk_cbe ev1 ev2 in
      (suid,OL.mkSingleton cb)) cmap_int in
  let rmap = RMap.init rmap in
  let cmap = CMap.init cmap in
  let assumes = ConstrMap.init assumes in
  let guards  = ConstrMap.mkEmpty () in
  let summary =  init_summary (rmap,cmap) (rmap,cmap) assumes guards in
  summary

let collect view prot =
  (* retrieves the  role params, and chan params*)
  let params = view.Iast.view_typed_vars in
  let roles, rest = List.partition (fun (t1,_) -> cmp_typ t1 role_typ) params in
  let channs, rest = List.partition (fun (t1,_) -> cmp_typ t1 chan_typ) params in
  (* creates def summary *)
  let def_sum = mk_def_summary roles channs in
  (* collects protocol's summary *)
  let res = collect prot in
  (* merge def summ w prot's summ *)
  let res = merge_all_seq def_sum res in 
  let amap = res.assumptions in
  let gmap = res.guards in
  (* normalize assumptions and guards *)
  let assume_norm = ConstrMap.map_data (fun assrt ->
    x_add_1 mk_order_normalization assrt
  ) amap in
  let guard_norm = ConstrMap.map_data (fun assrt ->
    x_add_1 mk_order_normalization assrt
  ) gmap in
  (assume_norm, guard_norm)

let collect view prot =
  let pr_out = pr_pair (add_str "\nAssumptions:" ConstrMap.string_of) (add_str "\nGuards:" ConstrMap.string_of) in
  Debug.no_1 "OS.collect" pr_none pr_out (collect view) prot


(* ------------------------------------------------------------------------ *)
(* Inserts order assumptions and proof obligations in the session protocol. *)
let insert_orders view prot =
  let amap,gmap = collect view prot in
  let insert sf = match sf with
    | SProt.SBase sb -> 
      begin 
        match sb with 
        | SProt.Base t -> 
            let uid = SBProt.get_uid t in 
            let loc = SBProt.get_base_pos t in
            let assume = ConstrMap.find amap uid in
            let guard = ConstrMap.find gmap uid in
            (* creates a sequence with order assumptions and guards *)
            let create_sequence orders name sess_pred_kind prot_session = match orders with
              | [] -> prot_session
              | _ -> 
                  let order_norm  = mk_and_list orders in
                  let pred = SProt.SBase (SProt.mk_session_predicate name [] [] ~orders:order_norm ~sess_pred_kind:(Assert sess_pred_kind) loc) in
                  let sequence = SProt.mk_session_seq_formula prot_session pred loc in
                  sequence
            in
            (* inserts order assumptions *)
            let seq = create_sequence assume "Assume" Assume sf in
            (* then, inserts order guards *)
            let seq = create_sequence guard "Guard" Guard seq in
            Some seq
        | _ -> None
      end
    | _ -> None in
  let fnc = (insert, (nonef, nonef)) in 
  let prot = x_add_1 SProt.trans_session_formula fnc prot in
  prot

let insert_orders view prot =
  let pr = SProt.string_of_session in
  Debug.no_1 "OS.insert_orders" pr pr (insert_orders view) prot
  

