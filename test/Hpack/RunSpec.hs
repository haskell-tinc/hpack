{-# LANGUAGE OverloadedStrings #-}
module Hpack.RunSpec (spec) where

import           Test.Hspec
import           Data.List

import           Hpack.ConfigSpec hiding (spec)
import           Hpack.Config
import           Hpack.Render
import           Hpack.Run

spec :: Spec
spec = do
  describe "renderPackage" $ do
    let renderPackage_ = renderPackage defaultRenderSettings
    it "renders a package" $ do
      renderPackage_ 0 [] package `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        ]

    it "aligns fields" $ do
      renderPackage_ 16 [] package `shouldBe` unlines [
          "name:           foo"
        , "version:        0.0.0"
        , "build-type:     Simple"
        , "cabal-version:  >= 1.10"
        ]

    it "includes description" $ do
      renderPackage_ 0 [] package {packageDescription = Just "foo\n\nbar\n"} `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "description: foo"
        , "             ."
        , "             bar"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        ]

    it "aligns description" $ do
      renderPackage_ 16 [] package {packageDescription = Just "foo\n\nbar\n"} `shouldBe` unlines [
          "name:           foo"
        , "version:        0.0.0"
        , "description:    foo"
        , "                ."
        , "                bar"
        , "build-type:     Simple"
        , "cabal-version:  >= 1.10"
        ]

    it "includes stability" $ do
      renderPackage_ 0 [] package {packageStability = Just "experimental"} `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "stability: experimental"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        ]

    it "includes copyright holder" $ do
      renderPackage_ 0 [] package {packageCopyright = ["(c) 2015 Simon Hengel"]} `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "copyright: (c) 2015 Simon Hengel"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        ]

    it "aligns copyright holders" $ do
      renderPackage_ 16 [] package {packageCopyright = ["(c) 2015 Foo", "(c) 2015 Bar"]} `shouldBe` unlines [
          "name:           foo"
        , "version:        0.0.0"
        , "copyright:      (c) 2015 Foo,"
        , "                (c) 2015 Bar"
        , "build-type:     Simple"
        , "cabal-version:  >= 1.10"
        ]

    it "includes extra-source-files" $ do
      renderPackage_ 0 [] package {packageExtraSourceFiles = ["foo", "bar"]} `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        , ""
        , "extra-source-files:"
        , "    foo"
        , "    bar"
        ]

    it "renders libray section" $ do
      renderPackage_ 0 [] package {packageLibrary = Just $ section library} `shouldBe` unlines [
          "name: foo"
        , "version: 0.0.0"
        , "build-type: Simple"
        , "cabal-version: >= 1.10"
        , ""
        , "library"
        , "  default-language: Haskell2010"
        ]

    context "when given list of existing fields" $ do
      it "retains field order" $ do
        renderPackage_ 16 ["cabal-version", "version", "name", "build-type"] package `shouldBe` unlines [
            "cabal-version:  >= 1.10"
          , "version:        0.0.0"
          , "name:           foo"
          , "build-type:     Simple"
          ]

      it "uses default field order for new fields" $ do
        renderPackage_ 16 ["name", "version", "cabal-version"] package `shouldBe` unlines [
            "name:           foo"
          , "version:        0.0.0"
          , "build-type:     Simple"
          , "cabal-version:  >= 1.10"
          ]

    context "when rendering executable section" $ do
      it "includes dependencies" $ do
        renderPackage_ 0 [] package {packageExecutables = [(section $ executable "foo" "Main.hs") {sectionDependencies = ["foo", "bar", "foo", "baz"]}]} `shouldBe` unlines [
            "name: foo"
          , "version: 0.0.0"
          , "build-type: Simple"
          , "cabal-version: >= 1.10"
          , ""
          , "executable foo"
          , "  main-is: Main.hs"
          , "  build-depends:"
          , "      foo"
          , "    , bar"
          , "    , foo"
          , "    , baz"
          , "  default-language: Haskell2010"
          ]

      it "includes GHC options" $ do
        renderPackage_ 0 [] package {packageExecutables = [(section $ executable "foo" "Main.hs") {sectionGhcOptions = ["-Wall", "-Werror"]}]} `shouldBe` unlines [
            "name: foo"
          , "version: 0.0.0"
          , "build-type: Simple"
          , "cabal-version: >= 1.10"
          , ""
          , "executable foo"
          , "  main-is: Main.hs"
          , "  ghc-options: -Wall -Werror"
          , "  default-language: Haskell2010"
          ]

  describe "renderConditional" $ do
    it "renders conditionals" $ do
      let conditional = (section $ Condition "os(windows)"){sectionDependencies = ["Win32"]}
      render defaultRenderSettings 0 (renderConditional conditional) `shouldBe` [
          "if os(windows)"
        , "  build-depends:"
        , "      Win32"
        ]

    it "renders nested conditionals" $ do
      let conditional = (section $ Condition "arch(i386)"){sectionGhcOptions = ["-threaded"], sectionConditionals = [innerConditional]}
          innerConditional = (section $ Condition "os(windows)"){sectionDependencies = ["Win32"]}
      render defaultRenderSettings 0 (renderConditional conditional) `shouldBe` [
          "if arch(i386)"
        , "  ghc-options: -threaded"
        , "  if os(windows)"
        , "    build-depends:"
        , "        Win32"
        ]

  describe "formatDescription" $ do
    it "formats description" $ do
      let description = unlines [
              "foo"
            , "bar"
            ]
      "description: " ++ formatDescription 0 description `shouldBe` intercalate "\n" [
          "description: foo"
        , "             bar"
        ]

    it "takes specified alignment into account" $ do
      let description = unlines [
              "foo"
            , "bar"
            , "baz"
            ]
      "description:   " ++ formatDescription 15 description `shouldBe` intercalate "\n" [
          "description:   foo"
        , "               bar"
        , "               baz"
        ]

    it "formats empty lines" $ do
      let description = unlines [
              "foo"
            , "   "
            , "bar"
            ]
      "description: " ++ formatDescription 0 description `shouldBe` intercalate "\n" [
          "description: foo"
        , "             ."
        , "             bar"
        ]

  describe "renderSourceRepository" $ do
    it "renders source-repository without subdir correctly" $ do
      let repository = SourceRepository "https://github.com/hspec/hspec" Nothing
      (render defaultRenderSettings 0 $ renderSourceRepository repository)
        `shouldBe` [
            "source-repository head"
          , "  type: git"
          , "  location: https://github.com/hspec/hspec"
          ]

    it "renders source-repository with subdir" $ do
      let repository = SourceRepository "https://github.com/hspec/hspec" (Just "hspec-core")
      (render defaultRenderSettings 0 $ renderSourceRepository repository)
        `shouldBe` [
            "source-repository head"
          , "  type: git"
          , "  location: https://github.com/hspec/hspec"
          , "  subdir: hspec-core"
          ]
