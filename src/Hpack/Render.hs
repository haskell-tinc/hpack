{-# LANGUAGE CPP #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Hpack.Render (
-- * AST
  Element (..)
, Value (..)

-- * Render
, RenderSettings (..)
, CommaStyle (..)
, defaultRenderSettings
, Alignment (..)
, Nesting
, render

-- * Utils
, sortFieldsBy

#ifdef TEST
, Lines (..)
, renderValue
, addSortKey
#endif
) where

import           Prelude ()
import           Prelude.Compat

import           Data.String
import           Data.List.Compat

data Value =
    Literal String
  | CommaSeparatedList [String]
  | LineSeparatedList [String]
  | WordList [String]
  deriving (Eq, Show)

data Element = Stanza String [Element] | Group Element Element | Field String Value
  deriving (Eq, Show)

data Lines = SingleLine String | MultipleLines [String] | MultipleLinesWithDot [String]
  deriving (Eq, Show)

data CommaStyle = LeadingCommas | TrailingCommas
  deriving (Eq, Show)

newtype Nesting = Nesting Int
  deriving (Eq, Show, Num, Enum)

newtype Alignment = Alignment Int
  deriving (Eq, Show, Num)

data RenderSettings = RenderSettings {
  renderSettingsIndentation :: Int
, renderSettingsFieldAlignment :: Alignment
, renderSettingsCommaStyle :: CommaStyle
} deriving (Eq, Show)

defaultRenderSettings :: RenderSettings
defaultRenderSettings = RenderSettings 2 0 LeadingCommas

render :: RenderSettings -> Nesting -> Element -> [String]
render settings nesting (Stanza name elements) = indent settings nesting name : renderElements settings (succ nesting) elements
render settings nesting (Group a b) = render settings nesting a ++ render settings nesting b
render settings nesting (Field name value) = renderField settings nesting name value

renderElements :: RenderSettings -> Nesting -> [Element] -> [String]
renderElements settings nesting = concatMap (render settings nesting)

renderField :: RenderSettings -> Nesting -> String -> Value -> [String]
renderField settings@RenderSettings{..} nesting name value = case renderValue settings value of
  SingleLine "" -> []
  SingleLine x -> [indent settings nesting (name ++ ": " ++ padding ++ x)]
  MultipleLines [] -> []
  MultipleLines xs -> (indent settings nesting name ++ ":") : map (indent settings $ succ nesting) xs
  MultipleLinesWithDot [] -> []
  MultipleLinesWithDot xs ->
      (indent settings nesting name ++ ":" ++ renderDot renderSettingsCommaStyle value) :
      map (indent settings $ succ nesting) xs
  where
    Alignment fieldAlignment = renderSettingsFieldAlignment
    padding = replicate (fieldAlignment - length name - 2) ' '

renderDot :: CommaStyle -> Value -> String
renderDot TrailingCommas (CommaSeparatedList _) = " .,"
renderDot _ _ = " ."

renderValue :: RenderSettings -> Value -> Lines
renderValue RenderSettings{..} v = case v of
  Literal s -> SingleLine s
  WordList ws -> SingleLine $ unwords ws
  LineSeparatedList xs -> renderLineSeparatedList renderSettingsCommaStyle xs
  CommaSeparatedList xs -> renderCommaSeparatedList renderSettingsCommaStyle xs

renderLineSeparatedList :: CommaStyle -> [String] -> Lines
renderLineSeparatedList style l
  | "." `elem` l = MultipleLinesWithDot out
  | otherwise = MultipleLines out
  where
    l' = filter (/= ".") l
    out = map (padding ++) l'
    padding = case style of
      LeadingCommas -> "  "
      TrailingCommas -> ""

renderCommaSeparatedList :: CommaStyle -> [String] -> Lines
renderCommaSeparatedList style l
  | hasDot = MultipleLinesWithDot out
  | otherwise = MultipleLines out
  where
    hasDot = "." `elem` l
    l' = filter (/= ".") l
    out = case style of
      LeadingCommas -> map renderLeadingComma $ zip (not hasDot : repeat False) l'
      TrailingCommas -> map renderTrailingComma $ reverse $ zip (True : repeat False) $ reverse l'

    renderLeadingComma :: (Bool, String) -> String
    renderLeadingComma (isFirst, x)
      | isFirst   = "  " ++ x
      | otherwise = ", " ++ x

    renderTrailingComma :: (Bool, String) -> String
    renderTrailingComma (isLast, x)
      | isLast    = x
      | otherwise = x ++ ","

instance IsString Value where
  fromString = Literal

indent :: RenderSettings -> Nesting -> String -> String
indent RenderSettings{..} (Nesting nesting) s = replicate (nesting * renderSettingsIndentation) ' ' ++ s

sortFieldsBy :: [String] -> [Element] -> [Element]
sortFieldsBy existingFieldOrder =
    map snd
  . sortOn fst
  . addSortKey
  . map (\a -> (existingIndex a, a))
  where
    existingIndex :: Element -> Maybe Int
    existingIndex (Field name _) = name `elemIndex` existingFieldOrder
    existingIndex _ = Nothing

addSortKey :: [(Maybe Int, a)] -> [((Int, Int), a)]
addSortKey = go (-1) . zip [0..]
  where
    go :: Int -> [(Int, (Maybe Int, a))] -> [((Int, Int), a)]
    go n xs = case xs of
      [] -> []
      (x, (Just y, a)) : ys -> ((y, x), a) : go y ys
      (x, (Nothing, a)) : ys -> ((n, x), a) : go n ys
