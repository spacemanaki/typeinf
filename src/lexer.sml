signature LEXER =
sig
   val make : (char * Pos.t, 'a) Reader.t -> (Token.t * Pos.t, 'a) Reader.t
   exception LexicalError of string
end

structure Lexer : LEXER =
struct

open Top
structure T = Token

fun fst (a, _) = a
fun snd (_, b) = b

exception LexicalError of string

(*
 * Extract an integer literal from a positional stream
 *)
fun getInt rdr s =
    let
       val isDigit = Char.isDigit o fst
       val (chars, s') = Reader.takeWhile rdr isDigit s
    in
       if length chars < 1 then
          (NONE, s)
       else
          case Int.fromString (String.implode (map fst chars)) of
              NONE => (NONE, s)
            | SOME n => (SOME (n, snd (hd chars)), s')
    end

(*
 * Drop leading whitespace from a positional stream
 *)
fun skipWS (rdr : (char * Pos.t, 'a) Reader.t) : 'a -> 'a =
    Reader.dropWhile rdr (Char.isSpace o fst)

(* Check is a stream starts with a comment *)
fun isComment rdr s =
    case Reader.take rdr 2 s of
        SOME ([(#"(", _), (#"*", _)], s') => true
      | _ => false

fun isSpace rdr s =
    case rdr s of
        SOME ((x, _), s) => Char.isSpace x
      | _ => false

(*
 * Drop a comment from a positional stream
 *)
fun skipComments (rdr : (char * Pos.t, 'a) Reader.t) (s : 'a) : 'a =
    let
       (* skip to end of comment block *)
       fun skip rdr s =
           case Reader.take rdr 2 s of
               SOME ([(#"*", _), (#")", _)], s') => s'
             | _ => case rdr s of
                        SOME (_, s') => skip rdr s'
                      | NONE => raise (LexicalError "unmatched comment block")
    in
       if isComment rdr s then
          skip rdr (Reader.drop rdr 2 s)
       else s
    end

(* Drop comments and whitespace until *)
fun trim (rdr : (char * Pos.t, 'a) Reader.t) (s : 'a) : 'a =
    if isComment rdr s then
       trim rdr (skipComments rdr s)
    else if isSpace rdr s then
       trim rdr (skipWS rdr s)
    else s

(*
 * Extract a keyword or identifier as a string from a positional stream
 *)
fun getWord rdr s =
    let
       fun notDelim #"(" = false
         | notDelim #")" = false
         | notDelim #"," = false
         | notDelim #"|" = false
         | notDelim ch = not (Char.isSpace ch)
       fun isSpecial x = notDelim x andalso Char.isPunct x
       fun isValid x = Char.isAlphaNum x orelse x = #"_"
    in
       case rdr s of
           NONE => (NONE, s)
         | SOME ((x, p), s') =>
           let
              val (chars, s'') =
                  if isSpecial x then
                     Reader.takeWhile rdr (isSpecial o fst) s
                  else Reader.takeWhile rdr (isValid o fst) s
           in
              if length chars < 1 then
                 (NONE, s)
              else (SOME (String.implode (map fst chars), snd (hd chars)), s'')
           end
    end

(* TODO: needs to be a Set build by previous infix declarations *)
fun isInfix "+" = true
  | isInfix "-" = true
  | isInfix "*" = true
  | isInfix "/" = true
  | isInfix _ = false

fun make (rdr : (char * Pos.t, 'a) Reader.t) : (T.t * Pos.t, 'a) Reader.t =
    fn t =>
       let
          val s = trim rdr t
       in
          case rdr s of

              NONE => NONE

            (* misc. punctuation *)
            | SOME ((#"(", p), s') => SOME ((T.LParen, p), s')
            | SOME ((#")", p), s') => SOME ((T.RParen, p), s')
            | SOME ((#"|", p), s') => SOME ((T.Bar,    p), s')
            | SOME ((#",", p), s') => SOME ((T.Comma,  p), s')

            (* type variables *)
            | SOME ((#"'", p), s') =>
              (case getWord rdr s' of
                   (SOME ("", _), _)  => raise CompilerBug "(Lexer.make) getWord returned empty string"
                 | (NONE, _)          => raise LexicalError "Expected type variable after apostrophe"
                 | (SOME (v, _), s'') => SOME ((T.TypeVar v, p), s''))

            (* integer literals *)
            | SOME ((x, _), s') =>
              if Char.isDigit x then
                 case getInt rdr s of
                     (NONE, _) => raise CompilerBug "(Lexer.make) getInt returned NONE, but stream starts with a digit"
                   | (SOME (n, p), s'') => SOME ((T.Num n, p), s'')
              else (* all other tokens *)
                 case getWord rdr s of
                     (SOME ("if",       p), s'') => SOME ((T.If,         p), s'')
                   | (SOME ("then",     p), s'') => SOME ((T.Then,       p), s'')
                   | (SOME ("else",     p), s'') => SOME ((T.Else,       p), s'')
                   | (SOME ("true",     p), s'') => SOME ((T.Bool true,  p), s'')
                   | (SOME ("false",    p), s'') => SOME ((T.Bool false, p), s'')
                   | (SOME ("fn",       p), s'') => SOME ((T.Fn,         p), s'')
                   | (SOME ("let",      p), s'') => SOME ((T.Let,        p), s'')
                   | (SOME ("in",       p), s'') => SOME ((T.In,         p), s'')
                   | (SOME ("end",      p), s'') => SOME ((T.End,        p), s'')
                   | (SOME ("case",     p), s'') => SOME ((T.Case,       p), s'')
                   | (SOME ("datatype", p), s'') => SOME ((T.Datatype,   p), s'')
                   | (SOME ("of",       p), s'') => SOME ((T.Of,         p), s'')
                   | (SOME ("val",      p), s'') => SOME ((T.Val,        p), s'')
                   | (SOME ("=",        p), s'') => SOME ((T.Eqls,       p), s'')
                   | (SOME ("=>",       p), s'') => SOME ((T.DArrow,     p), s'')
                   | (SOME ("->",       p), s'') => SOME ((T.TArrow,     p), s'')

                   | (SOME ("", _), _) => raise CompilerBug ("(Lexer.make) getWord returned empty string," ^
                                                             "but stream starts with #\"" ^ Char.toString x ^ "\"")
                   | (NONE, _) => raise LexicalError "Error lexing"
                   | (SOME (id, p), s'') =>
                     if Char.isUpper (String.sub (id, 0)) then
                        SOME ((T.Ctor id, p), s'')
                     else if isInfix id then
                        SOME ((T.Infix id, p), s'')
                     else SOME ((T.Id id, p), s'')
       end
end
