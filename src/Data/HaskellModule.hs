{-# LANGUAGE OverloadedStrings #-}
-- | A version of HaskellSource with slightly more semantics.
module Data.HaskellModule where

import Control.Applicative
import Data.ByteString.Char8 as B
import Text.Printf

import Data.HaskellSource
import Data.HaskellSource.Parse


-- | hint has `Interpreter.Extension`, but strings are simpler.
type ExtensionName = String

-- | import [qualified] <module-name> [as <qualified-name>]
type QualifiedModule = (String, Maybe String)

-- | Three key pieces of information about a Haskell Module:
--   the language extensions it enables,
--   the module's name (if any), and
--   the modules it imports.
data HaskellModule = HaskellModule
  { languageExtensions :: [ExtensionName]   , pragmaSource :: HaskellSource
  , moduleName         :: Maybe String      , moduleSource :: HaskellSource
  , importedModules    :: [QualifiedModule] , importSource :: HaskellSource
                                            , codeSource   :: HaskellSource
  } deriving (Show, Eq)


addExtension :: ExtensionName -> HaskellModule -> HaskellModule
addExtension e m = m
    { languageExtensions = extraExtensions e ++ languageExtensions m
    , pragmaSource       = extraSource e ++ pragmaSource m
    }
  where
    extraExtensions = return
    extraSource = return . return . languagePragma
    
    languagePragma = printf "{-# LANGUAGE %s #-}"

addImport :: QualifiedModule -> HaskellModule -> HaskellModule
addImport qm m = m
    { importedModules = extraModules qm ++ importedModules m
    , importSource    = extraSource qm ++ importSource m
    }
  where
    extraModules = return
    extraSource = return . return . importStatement
    
    importStatement (fullName, Nothing) =
        printf "import %s" fullName
    importStatement (fullName, Just qualifiedName) =
        printf "import qualified %s as %s" fullName qualifiedName


parseModule :: B.ByteString -> Maybe HaskellModule
parseModule = haskellModule . splitSource fourChunks . parseSource
  where
    haskellModule (Just [pS, mS, iS, cS]) = Just $ HaskellModule
      { languageExtensions = []   , pragmaSource = pS
      , moduleName = Nothing      , moduleSource = mS
      , importedModules = []      , importSource = iS
                                  , codeSource   = cS
      }
    haskellModule _ = Nothing
    
    fourChunks :: SourceParser ()
    fourChunks = do
        commentLines >> next_chunk
        moduleLine   >> next_chunk
        importLines  >> next_chunk
        remainingLines
    commentLines = (comment >> commentLines) <|> return ()
    moduleLine = module_declaration <|> return ()
    importLines = (import_declaration >> importLines) <|> return ()
    remainingLines = (line >> remainingLines) <|> eof
