(*
 * Copyright (c) 2018-2022 Tarides <contact@tarides.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Irmin_server
module Error = Error

module type S = Client.S

module Client = Client

type addr = Client_intf.addr

let config = Client.config

module Make_codec
    (IO : Client.IO)
    (Codec : Conn.Codec.S)
    (Store : Irmin.Generic_key.S) =
struct
  include Client.Make (IO) (Codec) (Store)
end

module Make (IO : Client.IO) (Store : Irmin.Generic_key.S) =
  Make_codec (IO) (Conn.Codec.Bin) (Store)

module Make_json (IO : Client.IO) (Store : Irmin.Generic_key.S) =
  Make_codec (IO) (Conn.Codec.Json) (Store)
