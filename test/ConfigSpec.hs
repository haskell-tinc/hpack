{-# LANGUAGE QuasiQuotes, OverloadedLists #-}
module ConfigSpec (
  main
, spec

, package
, executable
, library
) where

import           Helper

import           Data.String.Interpolate
import           System.IO.Silently

import           Config

main :: IO ()
main = hspec spec

package :: Package
package = Package "foo" "0.0.0" Nothing Nothing Nothing Nothing Nothing Nothing [] [] [] Nothing Nothing [] Nothing Nothing [] []

executable :: String -> String -> Executable
executable name main_ = Executable name main_ [] [] [] [] []

library :: Library
library = Library [] [] [] [] [] []

spec :: Spec
spec = around_ (inTempDirectoryNamed "foo") $ do
  describe "readPackageConfig" $ do
    it "accepts name" $ do
      writeFile "package.yaml" [i|
        name: bar
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageName = "bar"}

    it "accepts version" $ do
      writeFile "package.yaml" [i|
        version: 0.1.0
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageVersion = "0.1.0"}

    it "accepts synopsis" $ do
      writeFile "package.yaml" [i|
        synopsis: some synopsis
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageSynopsis = Just "some synopsis"}

    it "accepts description" $ do
      writeFile "package.yaml" [i|
        description: some description
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageDescription = Just "some description"}

    it "accepts category" $ do
      writeFile "package.yaml" [i|
        category: Data
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageCategory = Just "Data"}

    it "accepts author" $ do
      writeFile "package.yaml" [i|
        author: John Doe
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageAuthor = ["John Doe"]}

    it "accepts maintainer" $ do
      writeFile "package.yaml" [i|
        maintainer: John Doe <john.doe@example.com>
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageMaintainer = ["John Doe <john.doe@example.com>"]}

    it "accepts copyright" $ do
      writeFile "package.yaml" [i|
        copyright: (c) 2015 John Doe
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageCopyright = ["(c) 2015 John Doe"]}

    it "accepts stability" $ do
      writeFile "package.yaml" [i|
        stability: experimental
        |]
      Right c <- readPackageConfig "package.yaml"
      packageStability c `shouldBe` Just "experimental"

    it "accepts homepage URL" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        homepage: https://example.com/
        |]
      Right c <- readPackageConfig "package.yaml"
      packageHomepage c `shouldBe` Just "https://example.com/"

    it "infers homepage URL from github" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        |]
      Right c <- readPackageConfig "package.yaml"
      packageHomepage c `shouldBe` Just "https://github.com/hspec/hspec#readme"

    it "omits homepage URL if it is null" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        homepage: null
        |]
      Right c <- readPackageConfig "package.yaml"
      packageHomepage c `shouldBe` Nothing

    it "accepts bug-reports URL" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        bug-reports: https://example.com/issues
        |]
      Right c <- readPackageConfig "package.yaml"
      packageBugReports c `shouldBe` Just "https://example.com/issues"

    it "infers bug-reports URL from github" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        |]
      Right c <- readPackageConfig "package.yaml"
      packageBugReports c `shouldBe` Just "https://github.com/hspec/hspec/issues"

    it "omits bug-reports URL if it is null" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        bug-reports: null
        |]
      Right c <- readPackageConfig "package.yaml"
      packageBugReports c `shouldBe` Nothing

    it "accepts license" $ do
      writeFile "package.yaml" [i|
        license: MIT
        |]
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageLicense = Just "MIT"}

    it "infers license file" $ do
      writeFile "package.yaml" [i|
        name: foo
        |]
      touch "LICENSE"
      readPackageConfig "package.yaml" `shouldReturn` Right package {packageLicenseFile = Just "LICENSE"}

    it "accepts extra-source-files" $ do
      writeFile "package.yaml" [i|
        extra-source-files:
          - CHANGES.markdown
          - README.markdown
        |]
      Right c <- readPackageConfig "package.yaml"
      packageExtraSourceFiles c `shouldBe` ["CHANGES.markdown", "README.markdown"]

    it "accepts github" $ do
      writeFile "package.yaml" [i|
        github: hspec/hspec
        |]
      Right c <- readPackageConfig "package.yaml"
      packageSourceRepository c `shouldBe` Just "https://github.com/hspec/hspec"

    context "when reading library section" $ do
      it "accepts source-dirs" $ do
        writeFile "package.yaml" [i|
          library:
            source-dirs:
              - foo
              - bar
          |]
        Right c <- silence $ readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {librarySourceDirs = ["foo", "bar"]}

      it "warns when source-dirs don't exist on the system" $ do
        writeFile "package.yaml" [i|
        library:
          source-dirs: foo, bar
        |]
        capture_ (readPackageConfig "package.yaml") `shouldReturn`
         "The source-dir ‘foo, bar’ does not exist, check if you really meant it.\n"

      it "accepts default-extensions" $ do
        writeFile "package.yaml" [i|
          library:
            default-extensions:
              - Foo
              - Bar
          |]
        Right c <- readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {libraryDefaultExtensions = ["Foo", "Bar"]}

      it "accepts global default-extensions" $ do
        writeFile "package.yaml" [i|
          default-extensions:
            - Foo
            - Bar
          library: {}
          |]
        Right c <- readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {libraryDefaultExtensions = ["Foo", "Bar"]}

      it "accepts global source-dirs" $ do
        writeFile "package.yaml" [i|
          source-dirs:
            - foo
            - bar
          library: {}
          |]
        Right c <- silence $ readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {librarySourceDirs = ["foo", "bar"]}

      it "allows to specify exposed-modules" $ do
        writeFile "package.yaml" [i|
          library:
            source-dirs: src
            exposed-modules: Foo
          |]
        touch "src/Foo.hs"
        touch "src/Bar.hs"
        Right c <- readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {librarySourceDirs = ["src"], libraryExposedModules = ["Foo"], libraryOtherModules = ["Bar"]}

      it "allows to specify other-modules" $ do
        writeFile "package.yaml" [i|
          library:
            source-dirs: src
            other-modules: Bar
          |]
        touch "src/Foo.hs"
        touch "src/Bar.hs"
        Right c <- readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {librarySourceDirs = ["src"], libraryExposedModules = ["Foo"], libraryOtherModules = ["Bar"]}

      it "allows to specify both exposed-modules and other-modules" $ do
        writeFile "package.yaml" [i|
          library:
            source-dirs: src
            exposed-modules: Foo
            other-modules: Bar
          |]
        touch "src/Baz.hs"
        Right c <- readPackageConfig "package.yaml"
        packageLibrary c `shouldBe` Just library {librarySourceDirs = ["src"], libraryExposedModules = ["Foo"], libraryOtherModules = ["Bar"]}

      context "when neither exposed-module nor other-module are specified" $ do
        it "exposes all modules" $ do
          writeFile "package.yaml" [i|
            library:
              source-dirs: src
            |]
          touch "src/Foo.hs"
          touch "src/Bar.hs"
          Right c <- readPackageConfig "package.yaml"
          packageLibrary c `shouldBe` Just library {librarySourceDirs = ["src"], libraryExposedModules = ["Bar", "Foo"]}

    context "when reading executable section" $ do
      it "reads executable section" $ do
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: driver/Main.hs
          |]
        Right c <- readPackageConfig "package.yaml"
        packageExecutables c `shouldBe` [executable "foo" "driver/Main.hs"]

      it "accepts source-dirs" $ do
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: Main.hs
              source-dirs:
                - foo
                - bar
          |]
        Right c <- silence $ readPackageConfig "package.yaml"
        packageExecutables c `shouldBe` [(executable "foo" "Main.hs") {executableSourceDirs = ["foo", "bar"]}]

      it "accepts global source-dirs" $ do
        writeFile "package.yaml" [i|
          source-dirs:
            - foo
            - bar
          executables:
            foo:
              main: Main.hs
          |]
        Right c <- silence $ readPackageConfig "package.yaml"
        packageExecutables c `shouldBe` [(executable "foo" "Main.hs") {executableSourceDirs = ["foo", "bar"]}]

      it "infers other-modules" $ do
        touch "src/Main.hs"
        touch "src/Foo.hs"
        touch "src/Bar.hs"
        touch "src/Baz.lhs"
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: Main.hs
              source-dirs: src
          |]
        Right [r] <- fmap packageExecutables <$> readPackageConfig "package.yaml"
        executableOtherModules r `shouldBe` ["Bar", "Baz", "Foo"]

      it "allows to specify other-modules" $ do
        touch "src/Foo.hs"
        touch "src/Bar.hs"
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: Main.hs
              source-dirs: src
              other-modules: Baz
          |]
        Right [r] <- fmap packageExecutables <$> readPackageConfig "package.yaml"
        executableOtherModules r `shouldBe` ["Baz"]

      it "accepts default-extensions" $ do
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: driver/Main.hs
              default-extensions:
                - Foo
                - Bar
          |]
        Right c <- readPackageConfig "package.yaml"
        packageExecutables c `shouldBe` [(executable "foo" "driver/Main.hs") {executableDefaultExtensions = ["Foo", "Bar"]}]

      it "accepts global default-extensions" $ do
        writeFile "package.yaml" [i|
          default-extensions:
            - Foo
            - Bar
          executables:
            foo:
              main: driver/Main.hs
          |]
        Right c <- readPackageConfig "package.yaml"
        packageExecutables c `shouldBe` [(executable "foo" "driver/Main.hs") {executableDefaultExtensions = ["Foo", "Bar"]}]

      it "accepts GHC options" $ do
        writeFile "package.yaml" [i|
          executables:
            foo:
              main: driver/Main.hs
              ghc-options: -Wall
          |]
        readPackageConfig "package.yaml" `shouldReturn` Right package {packageExecutables = [(executable "foo" "driver/Main.hs") {executableGhcOptions = ["-Wall"]}]}

      it "accepts global GHC options" $ do
        writeFile "package.yaml" [i|
          ghc-options: -Wall
          executables:
            foo:
              main: driver/Main.hs
          |]
        readPackageConfig "package.yaml" `shouldReturn` Right package {packageExecutables = [(executable "foo" "driver/Main.hs") {executableGhcOptions = ["-Wall"]}]}

    context "when reading test section" $ do
      it "reads test section" $ do
        writeFile "package.yaml" [i|
          tests:
            spec:
              main: test/Spec.hs
          |]
        readPackageConfig "package.yaml" `shouldReturn` Right package {packageTests = [executable "spec" "test/Spec.hs"]}

      it "accepts single dependency" $ do
        writeFile "package.yaml" [i|
          tests:
            spec:
              main: test/Spec.hs
              dependencies: hspec
          |]
        readPackageConfig "package.yaml" `shouldReturn` Right package {packageTests = [(executable "spec" "test/Spec.hs") {executableDependencies = [["hspec"]]}]}

      it "accepts list of dependencies" $ do
        writeFile "package.yaml" [i|
          tests:
            spec:
              main: test/Spec.hs
              dependencies:
                - hspec
                - QuickCheck
          |]
        readPackageConfig "package.yaml" `shouldReturn` Right package {packageTests = [(executable "spec" "test/Spec.hs") {executableDependencies = [["hspec", "QuickCheck"]]}]}

      context "when both top-level and section specific dependencies are specified" $ do
        it "combines dependencies" $ do
          writeFile "package.yaml" [i|
            dependencies:
              - base

            tests:
              spec:
                main: test/Spec.hs
                dependencies: hspec
            |]
          readPackageConfig "package.yaml" `shouldReturn` Right package {packageTests = [(executable "spec" "test/Spec.hs") {executableDependencies = [["base"], ["hspec"]]}]}

    context "when package.yaml can not be parsed" $ do
      it "returns an error" $ do
        writeFile "package.yaml" [i|
          foo: bar
          foo baz
          |]
        readPackageConfig "package.yaml" `shouldReturn` Left "package.yaml:3:10: could not find expected ':' while scanning a simple key"

    context "when package.yaml is invalid" $ do
      it "returns an error" $ do
        writeFile "package.yaml" [i|
          executables:
            foo:
              ain: driver/Main.hs
          |]
        readPackageConfig "package.yaml" `shouldReturn` Left "package.yaml: The key \"main\" was not found"
