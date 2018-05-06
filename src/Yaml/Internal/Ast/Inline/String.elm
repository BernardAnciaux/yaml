module Yaml.Internal.Ast.Inline.String exposing (parser)

{-|

@docs parser

-}

import Parser exposing (..)


parser : Maybe Char -> Parser String
parser maybeEndChar =
    succeed identity
        |. spaces
        |= andThen (\n -> strings maybeEndChar [ n ]) (stringHead maybeEndChar)
        |. spaces


strings : Maybe Char -> List String -> Parser String
strings maybeEndChar revStrings =
    oneOf
        [ andThen (\n -> strings maybeEndChar (n :: revStrings)) (nextString maybeEndChar)
        , succeed (List.reverse revStrings |> String.concat)
        ]


nextString : Maybe Char -> Parser String
nextString maybeEndChar =
    delayedCommitMap (\spaces string -> spaces ++ string) keepSpaces <|
        succeed identity
            |= stringTail maybeEndChar


stringHead : Maybe Char -> Parser String
stringHead maybeEndChar =
    keep (Exactly 1) <| \char -> char /= ',' && char /= '\n' && char /= ' ' && isNotEnd maybeEndChar char


stringTail : Maybe Char -> Parser String
stringTail maybeEndChar =
    keep oneOrMore <| \char -> char /= ',' && char /= '\n' && char /= ' ' && isNotEnd maybeEndChar char


isNotEnd : Maybe Char -> Char -> Bool
isNotEnd maybeEndChar char =
    case maybeEndChar of
        Just endChar ->
            char /= endChar

        Nothing ->
            True



-- HELPERS


spaces : Parser ()
spaces =
    ignore zeroOrMore (\char -> char == ' ')


keepSpaces : Parser String
keepSpaces =
    keep zeroOrMore (\c -> c == ' ')