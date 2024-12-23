module Yaml.Encode exposing
    ( Encoder
    , toString
    , string, int, float, bool, null, value
    , list, record, dict
    , document
    , safeEncodeString, safeEncodeKey, safeEncodeMultilineString
    )

{-| Turn Elm values into [YAML](https://yaml.org). You use `Yaml.Encode` in a very similar
way to how you use `Json.Encode`. For an excellent introduction to encoding (with `Json.Encode`)
have a look at
[this blog post](https://korban.net/posts/elm/2018-09-12-generate-json-from-elm-values-json-encode/).


## Table of Contents

  - **Primitives**: [int](#int), [string](#string), [bool](#bool), [float](#float), [null](#null), [value](#value)
  - **Data Structures**: [list](#list), [record](#record), [dict](#dict)
  - **YAML specifics**: [document](#document)

@docs Encoder


# Run Encoders

@docs toString


# Primitives

@docs string, int, float, bool, null, value


# Data Structures

@docs list, record, dict


# YAML specific details

@docs document

-}

import Dict exposing (Dict)
import Yaml.Parser.Ast exposing (Value(..))
import String.Extra exposing (quote)


safeEncodeString : String -> Encoder
safeEncodeString s =
    if String.contains "\n" s then
        safeEncodeMultilineString s
    else
        encodeSpecialChars s
            |> encodeQuotes
            |> quote
            |> string

encodeQuotes : String -> String
encodeQuotes s =
    if String.contains "\"" s then
        String.replace "\"" "\\\"" s
    else
        s

encodeSpecialChars : String -> String
encodeSpecialChars s =
    if String.startsWith "*" s || String.startsWith "!" s || String.startsWith "&" s then
        "\\" ++ s
    else
        s

safeEncodeMultilineString : String -> Encoder
safeEncodeMultilineString s =
    string (String.join "\n" (List.map encodeQuotes (String.split "\n" s)))

safeEncodeKey : String -> Encoder
safeEncodeKey key =
    if String.contains ":" key || String.contains " " key then
        string (quote key)
    else
        string key


{-| Keep track of Encoder state while encoding
-}
type alias EncoderState =
    { col : Int -- Current column
    , indent : Int -- Encoder indent amouont
    , inRecord : Bool -- Encoding context (in a record or not)
    }


{-| Initialise blank encoder state
-}
initState : Int -> EncoderState
initState indent =
    { col = 0
    , indent = indent
    , inRecord = False
    }


{-| A value that knows how to encode Elm values into YAML.
-}
type Encoder
    = Encoder (EncoderState -> String)


{-| Encoding context
-}
type Context
    = Oneline
    | Multiline



-- RUN ENCODERS


{-| Encode a given Elm value into a YAML formatted string.

The first argument specifies the amount of indentation in the
resulting string.

    toString 0 (int 4) --> "4"

    toString 0 (list int [ 1, 2, 3 ]) --> "[1, 2, 3]"

    toString 2 (list int [ 1, 2, 3 ])
    --> "- 1\n- 2\n- 3"

You can also embed your encoded values into a YAML document:

    toString 2 (document
                  <| record [ ( "hello", string "world" ) ])
    --> "---\nhello: world\n..."

-}
toString : Int -> Encoder -> String
toString indent =
    initState indent
        |> internalConvertToString


internalConvertToString : EncoderState -> Encoder -> String
internalConvertToString state (Encoder encoderFn) =
    encoderFn state



-- PRIMITIVES
-- Primitive values care about their encoding context because records can be
-- encoded with a single space after the colon if the value is primitive or
-- an inline list or record, otherwise a newline is required.


{-| Encode a `String` into a YAML string.

    toString 0 (string "") --> ""

    toString 0 (string "hello") --> "hello"

-}
string : String -> Encoder
string s =
    Encoder
        (withContext Oneline s)


{-| Encode an `Int` into a YAML int.

    toString 0 (int 42) --> "42"

    toString 0 (int -7) --> "-7"

    toString 0 (int 0) --> "0"

-}
int : Int -> Encoder
int i =
    Encoder
        (withContext Oneline (String.fromInt i))


{-| Encode a `Float` into a YAML float.

    nan : Float
    nan = (0/0)

    infinity : Float
    infinity = (1/0)

    toString 0 (float 3.14)      --> "3.14"

    toString 0 (float -42)       --> "-42"

    toString 0 (float 0.0)       --> "0"

    toString 0 (float nan)       --> ".nan"

    toString 0 (float -infinity) --> "-.inf"

-}
float : Float -> Encoder
float f =
    let
        sign =
            if f < 0 then
                "-"

            else
                ""

        val =
            if isNaN f then
                ".nan"

            else if isInfinite f then
                sign ++ ".inf"

            else
                String.fromFloat f
    in
    Encoder
        (withContext Oneline val)


{-| Encode a `Bool` into a YAML bool.

    toString 0 (bool True) --> "true"

    toString 0 (bool False) --> "false"

-}
bool : Bool -> Encoder
bool b =
    Encoder
        (withContext Oneline
            (if b then
                "true"

             else
                "false"
            )
        )


{-| Encode a YAML `null` value

    toString 0 null --> "null"

    toString 2 (record [ ("null", null) ])
    --> "null: null"

-}
null : Encoder
null =
    Encoder (withContext Oneline "null")


{-| Encode a `Value` as produced by `Yaml.Decode.value`
-}
value : Value -> Encoder
value val =
    case val of
        String_ s ->
            string s

        Float_ f ->
            float f

        Int_ i ->
            int i

        Null_ ->
            null

        Bool_ b ->
            bool b

        List_ l ->
            list value l

        Record_ r ->
            dict identity value r

        Anchor_ name rval ->
            anchor name value rval

        Alias_ name ->
            alias_ name



-- DATA STRUCTURES


{-| Encode a `List` into a YAML list.

    toString 0 (list float [1.1, 2.2, 3.3])
    --> "[1.1, 2.2, 3.3]"

    toString 2 (list string ["a", "b"])
    --> "- a\n- b"

-}
list : (a -> Encoder) -> List a -> Encoder
list encode l =
    Encoder
        (\state ->
            if List.isEmpty l then
                withContext Oneline "[]" state

            else
                case state.indent of
                    0 ->
                        withContext Oneline (encodeInlineList encode l) state

                    _ ->
                        withContext Multiline (encodeList encode state l) state
        )


encodeInlineList : (a -> Encoder) -> List a -> String
encodeInlineList encode l =
    "["
        ++ (List.map (encode >> toString 0) l
                |> String.join ", "
           )
        ++ "]"


encodeList : (a -> Encoder) -> EncoderState -> List a -> String
encodeList encode state l =
    let
        newState : EncoderState
        newState =
            { state
                | col = state.col + state.indent
                , inRecord = False
            }

        listElement : a -> String
        listElement val =
            "- "
                ++ String.repeat (state.indent - 2) " "
                ++ (internalConvertToString newState << encode)
                    val
    in
    List.map listElement l
        |> String.join (indentAfter state "\n")


{-| Encode a `Dict` into a YAML record.

    import Dict


    toString 0 (dict
                  identity
                  int (Dict.singleton "Sue" 38))
    --> "{Sue: 38}"

    toString 2 (dict
                  identity
                  string (Dict.fromList [ ("hello", "foo")
                                        , ("world", "bar")
                                        ]
                         )
               )
    --> "hello: foo\nworld: bar"

-}
dict : (k -> String) -> (v -> Encoder) -> Dict k v -> Encoder
dict key val r =
    Encoder
        (\state ->
            if Dict.isEmpty r then
                withContext Oneline "{}" state

            else
                case state.indent of
                    0 ->
                        withContext Oneline (encodeInlineDict key val r) state

                    _ ->
                        withContext Multiline (encodeDict key val state r) state
        )


encodeInlineDict : (k -> String) -> (v -> Encoder) -> Dict k v -> String
encodeInlineDict key val r =
    let
        stringify : Dict k v -> List String
        stringify d =
            d
                |> Dict.map (\_ -> val >> toString 0)
                |> Dict.toList
                |> List.map (\( fst, snd ) -> key fst ++ ": " ++ snd)
    in
    "{"
        ++ (stringify r |> String.join ", ")
        ++ "}"


encodeDict : (k -> String) -> (v -> Encoder) -> EncoderState -> Dict k v -> String
encodeDict key val state r =
    let
        recordElement : ( k, v ) -> String
        recordElement ( key_, val_ ) =
            let
                newState =
                    { state | inRecord = True, col = state.col + state.indent }
            in
            key key_
                ++ ":"
                ++ (internalConvertToString newState << val) val_
    in
    Dict.toList r
        |> List.map recordElement
        |> String.join (indentAfter state "\n")


{-| Encode a YAML record.

    toString 0 (record [ ( "name", string "Sally" )
                       , ( "height", int 187)
                       ]
               )
    --> "{name: Sally, height: 187}"

    toString 2 (record [ ( "foo", int 42 )
                       , ( "bar", float 3.14 )
                       ]
               )
    --> "foo: 42\nbar: 3.14"

-}
record : List ( String, Encoder ) -> Encoder
record r =
    Encoder
        (\state ->
            if List.isEmpty r then
                withContext Oneline "{}" state

            else
                case state.indent of
                    0 ->
                        withContext Oneline (encodeInlineRecord r) state

                    _ ->
                        withContext Multiline (encodeRecord state r) state
        )


encodeInlineRecord : List ( String, Encoder ) -> String
encodeInlineRecord r =
    let
        stringify : List ( String, Encoder ) -> List String
        stringify vals =
            List.map
                (\pair ->
                    Tuple.first pair ++ ": " ++ (Tuple.second >> toString 0) pair
                )
                vals
    in
    "{" ++ (stringify r |> String.join ", ") ++ "}"


encodeRecord : EncoderState -> List ( String, Encoder ) -> String
encodeRecord state r =
    let
        recordElement : ( String, Encoder ) -> String
        recordElement ( key, val ) =
            let
                newState =
                    { state | inRecord = True, col = state.col + state.indent }

                encodedValue =
                    internalConvertToString newState val
            in
            key
                ++ ":"
                ++ encodedValue
    in
    List.map recordElement r
        |> String.join (indentAfter state "\n")



--|> String.append (indentAfter state (prefixed "\n" state ""))


{-| Encode a YAML document

YAML "documents" are demarked by "`---`" at the beginning and
"`...`" at the end. This encoder places a value into a
demarcated YAML document.

    toString 0 (document <| string "hello")
    --> "---\nhello\n..."

    toString 2 (document
                  <| record [ ("hello", int 5)
                            , ("foo", int 3)
                            ]
               )
    --> "---\nhello: 5\nfoo: 3\n..."

-}
document : Encoder -> Encoder
document val =
    Encoder
        (\state ->
            "---\n"
                ++ internalConvertToString state val
                ++ "\n..."
        )



-- HELPERS


anchor : String -> (Value -> Encoder) -> Value -> Encoder
anchor name encode val =
    Encoder
        (\state ->
            "&" ++ name ++ toString state.indent (encode val)
        )


alias_ : String -> Encoder
alias_ name =
    Encoder
        (\_ ->
            "*" ++ name
        )


indentAfter : EncoderState -> String -> String
indentAfter state s =
    s ++ String.repeat state.col " "


withContext : Context -> String -> EncoderState -> String
withContext context val state =
    case ( context, state.inRecord ) of
        ( Oneline, True ) ->
            " " ++ val

        ( Multiline, True ) ->
            "\n" ++ String.repeat state.col " " ++ val

        _ ->
            val
