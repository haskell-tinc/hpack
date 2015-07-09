{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Hpack.Run (
  run
-- exported for testing
, renderPackage
, renderSection
, renderSourceRepository
, formatDescription
) where

import           Prelude ()
import           Prelude.Compat

import           Control.Monad
import           Data.Char
import           Data.Maybe
import           Data.List.Compat
import           System.Exit.Compat

import           Hpack.Util
import           Hpack.Config

run :: IO ([String], FilePath, String)
run = do
  mPackage <- readPackageConfig packageConfig
  case mPackage of
    Right (warnings, package) -> do
      let cabalFile = packageName package ++ ".cabal"

      old <- tryReadFile cabalFile

      let alignment = fromMaybe 16 (old >>= sniffAlignment)
          output = renderPackage alignment (maybe [] extractFieldOrderHint old) package
      return (warnings, cabalFile, output)
    Left err -> die err

renderPackage :: Int -> [String] -> Package -> String
renderPackage alignment existingFieldOrder Package{..} = intercalate "\n" sections
  where
    sections :: [String]
    sections = catMaybes [
        header
      , extraSourceFiles
      , dataFiles
      , sourceRepository
      , library
      ] ++ renderExecutables packageExecutables ++ renderTests packageTests

    header = Just (unlines $ map formatField sortedFields)

    extraSourceFiles = guard (not . null $ packageExtraSourceFiles) >> Just (unlines $ "extra-source-files:" : map ("  " ++) packageExtraSourceFiles)
    dataFiles = guard (not . null $ packageDataFiles) >> Just (unlines $ "data-files:" : map ("  " ++) packageDataFiles)

    sourceRepository = renderSourceRepository <$> packageSourceRepository

    library = renderLibrary <$> packageLibrary

    padding name = replicate (alignment - length name - 2) ' '

    formatField :: (String, String) -> String
    formatField (name, value) = name ++ ": " ++ padding name ++ value

    sortedFields :: [(String, String)]
    sortedFields = foldr insertByDefaultFieldOrder (sortBy orderingForExistingFields existing) new
      where
        (existing, new) = partition ((`elem` existingFieldOrder) . fst) fields

        insertByDefaultFieldOrder :: (String, a) -> [(String, a)] -> [(String, a)]
        insertByDefaultFieldOrder x@(key1, _) xs = case xs of
          [] -> [x]
          y@(key2, _) : ys -> if index key1 < index key2 then x : y : ys else y : insertByDefaultFieldOrder x ys
          where
            index :: String -> Maybe Int
            index = (`elemIndex` defaultFieldOrder)

    orderingForExistingFields :: (String, a) -> (String, a) -> Ordering
    orderingForExistingFields (key1, _) (key2, _) = index key1 `compare` index key2
      where
        index :: String -> Maybe Int
        index = (`elemIndex` existingFieldOrder)

    fields :: [(String, String)]
    fields = mapMaybe (\(name, value) -> (,) name <$> value) $ [
        ("name", Just packageName)
      , ("version", Just packageVersion)
      , ("synopsis", packageSynopsis)
      , ("description", (formatDescription alignment <$> packageDescription))
      , ("category", packageCategory)
      , ("stability", packageStability)
      , ("homepage", packageHomepage)
      , ("bug-reports", packageBugReports)
      , ("author", formatList packageAuthor)
      , ("maintainer", formatList packageMaintainer)
      , ("copyright", formatList packageCopyright)
      , ("license", packageLicense)
      , ("license-file", packageLicenseFile)
      , ("build-type", Just "Simple")
      , ("cabal-version", Just ">= 1.10")
      ]

    formatList :: [String] -> Maybe String
    formatList xs = guard (not $ null xs) >> (Just $ intercalate separator xs)
      where
        separator = ",\n" ++ replicate alignment ' '

    defaultFieldOrder :: [String]
    defaultFieldOrder = map fst fields

formatDescription :: Int -> String -> String
formatDescription alignment description = case map emptyLineToDot $ lines description of
  x : xs -> intercalate "\n" (x : map (indentation ++) xs)
  [] -> ""
  where
    n = max alignment (length "description: ")
    indentation = replicate n ' '

    emptyLineToDot xs
      | isEmptyLine xs = "."
      | otherwise = xs

    isEmptyLine = all isSpace

renderSourceRepository :: SourceRepository -> String
renderSourceRepository SourceRepository{..} = concat [
    "source-repository head\n"
  , "  type: git\n"
  , "  location: " ++ sourceRepositoryUrl ++ "\n"
  , maybe "" (("  subdir: " ++) . (++ "\n")) sourceRepositorySubdir
  ]

renderExecutables :: [Section Executable] -> [String]
renderExecutables = map renderExecutable

renderExecutable :: Section Executable -> String
renderExecutable section@(sectionData -> Executable{..}) =
     "executable "
  ++ executableName ++ "\n"
  ++ renderExecutableSection section

renderTests :: [Section Executable] -> [String]
renderTests = map renderTest

renderTest :: Section Executable -> String
renderTest section@(sectionData -> Executable{..}) =
     "test-suite " ++ executableName ++ "\n"
  ++ "  type: exitcode-stdio-1.0\n"
  ++ renderExecutableSection section

renderExecutableSection :: Section Executable -> String
renderExecutableSection section@(sectionData -> Executable{..}) =
     "  main-is: " ++ executableMain ++ "\n"
  ++ renderSection 1 section
  ++ renderOtherModules executableOtherModules
  ++ "  default-language: Haskell2010\n"

renderLibrary :: Section Library -> String
renderLibrary section@(sectionData -> Library{..}) =
    "library\n"
  ++ renderSection 1 section
  ++ renderExposedModules libraryExposedModules
  ++ renderOtherModules libraryOtherModules
  ++ "  default-language: Haskell2010\n"

newtype Nesting = Nesting Int
  deriving (Num, Enum)

indent :: Nesting -> [String] -> String
indent (Nesting n) = unlines . map indentLine
  where
    indentLine "" = ""
    indentLine s = replicate (n * 2) ' ' ++ s

renderSection :: Nesting -> Section a -> String
renderSection nesting Section{..} =
     renderSourceDirs sectionSourceDirs
  ++ indent nesting (renderDependencies sectionDependencies)
  ++ indent nesting (renderDefaultExtensions sectionDefaultExtensions)
  ++ indent nesting (renderGhcOptions sectionGhcOptions)
  ++ indent nesting (renderCppOptions sectionCppOptions)
  ++ renderConditionals nesting sectionConditionals

renderConditionals :: Nesting -> [Section Condition] -> String
renderConditionals nesting = concatMap (renderConditional nesting)

renderConditional :: Nesting -> Section Condition -> String
renderConditional nesting section = condition ++ renderSection (succ nesting) section
  where
    condition = indent nesting ["if " ++ conditionCondition (sectionData section)]

renderSourceDirs :: [String] -> String
renderSourceDirs dirs
  | null dirs = ""
  | otherwise = "  hs-source-dirs: " ++ intercalate ", " dirs ++ "\n"

renderExposedModules :: [String] -> String
renderExposedModules modules
  | null modules = ""
  | otherwise = "  exposed-modules:\n" ++ (unlines $ map ("      " ++) modules)

renderOtherModules :: [String] -> String
renderOtherModules modules
  | null modules = ""
  | otherwise = "  other-modules:\n" ++ (unlines $ map ("      " ++) modules)

renderDependencies :: [Dependency] -> [String]
renderDependencies dependencies
  | null dependencies = []
  | otherwise = "build-depends:" : map render (zip (True : repeat False) dependencies)
  where
    render :: (Bool, Dependency) -> String
    render (isFirst, dependency)
      | isFirst   = "    " ++ dependencyName dependency
      | otherwise = "  , " ++ dependencyName dependency

renderGhcOptions :: [GhcOption] -> [String]
renderGhcOptions = renderOptions "ghc-options"

renderCppOptions :: [GhcOption] -> [String]
renderCppOptions = renderOptions "cpp-options"

renderDefaultExtensions :: [String] -> [String]
renderDefaultExtensions = renderOptions "default-extensions"

renderOptions :: String -> [String] -> [String]
renderOptions field options
  | null options = []
  | otherwise = [field ++ ": " ++ unwords options]
