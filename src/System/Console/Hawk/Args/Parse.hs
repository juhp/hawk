{-# LANGUAGE OverloadedStrings, PackageImports, ScopedTypeVariables #-}
-- | In which Hawk's command-line arguments are structured into a `HawkSpec`.
module System.Console.Hawk.Args.Parse (parseArgs) where

import Data.Char                                 (isSpace)
import Data.Maybe
import "mtl" Control.Monad.Trans

import Control.Monad.Trans.OptionParser
import Control.Monad.Trans.Uncertain
import qualified System.Console.Hawk.Args.Option as Option
import           System.Console.Hawk.Args.Option (HawkOption, options)
import           System.Console.Hawk.Args.Spec
import           System.Console.Hawk.Context.Dir

-- $setup
-- >>> let testP parser = runUncertainIO . runOptionParserT options parser


-- | (record separator, field separator)
type CommonSeparators = (Separator, Separator)

-- | Extract '-D' and '-d'. We perform this step separately because those two
--   delimiters are used by both the input and output specs.
-- 
-- >>> let test = testP commonSeparators
-- 
-- >>> test []
-- (Delimiter "\n",Whitespace)
-- 
-- >>> test ["-D\\n", "-d\\t"]
-- (Delimiter "\n",Delimiter "\t")
-- 
-- >>> test ["-D|", "-d,"]
-- (Delimiter "|",Delimiter ",")
commonSeparators :: forall m. (Functor m, Monad m)
                 => OptionParserT HawkOption m CommonSeparators
commonSeparators = do
    r <- consumeLastSeparator Option.RecordDelimiter defaultRecordSeparator
    f <- consumeLastSeparator Option.FieldDelimiter  defaultFieldSeparator
    return (r, f)
  where
    consumeLastSeparator :: HawkOption -> Separator -> OptionParserT HawkOption m Separator
    consumeLastSeparator opt def = fromMaybe def <$> consumeLast opt separatorConsumer

    separatorConsumer :: OptionConsumerT m Separator
    separatorConsumer = maybe Whitespace Delimiter <$> Option.delimiterConsumer


-- | The input delimiters have already been parsed, but we still need to
--   interpret them and to determine the input source.
-- 
-- >>> :{
-- let test = testP $ do { c <- commonSeparators
--                       ; _ <- consumeExtra stringConsumer  -- skip expr
--                       ; i <- inputSpec c
--                       ; lift $ print $ inputSource i
--                       ; lift $ print $ inputFormat i
--                       }
-- :}
-- 
-- >>> test []
-- UseStdin
-- Records (Delimiter "\n") (Fields Whitespace)
-- 
-- TODO: why is this test failing?
-- -->>> test ["-d", "-a", "L.reverse"]
-- --UseStdin
-- --Records (Delimiter "\n") RawRecord
-- 
-- TODO: why is this test failing?
-- -->>> test ["-D", "-a", "B.reverse"]
-- --UseStdin
-- --RawStream
-- 
-- >>> test ["-d:", "-m", "L.head", "/etc/passwd"]
-- InputFile "/etc/passwd"
-- Records (Delimiter "\n") (Fields (Delimiter ":"))
inputSpec :: (Functor m, Monad m)
          => CommonSeparators -> OptionParserT HawkOption m InputSpec
inputSpec (rSep, fSep) = InputSpec <$> source <*> format
  where
    source = do
        r <- consumeExtra stringConsumer
        return $ case r of
          Nothing -> UseStdin
          Just f  -> InputFile f
    format = return streamFormat
    streamFormat | rSep == Delimiter "" = RawStream
                 | otherwise            = Records rSep recordFormat
    recordFormat | fSep == Delimiter "" = RawRecord
                 | otherwise            = Fields fSep

-- | The output delimiters take priority over the input delimiters, regardless
--   of the order in which they appear.
-- 
-- >>> :{
-- let test = testP $ do { c <- commonSeparators
--                       ; o <- outputSpec c
--                       ; let OutputFormat r f = outputFormat o
--                       ; lift $ print $ outputSink o
--                       ; lift $ print (r, f)
--                       }
-- :}
-- 
-- >>> test []
-- UseStdout
-- ("\n"," ")
-- 
-- >>> test ["-D;", "-d", "-a", "L.reverse"]
-- UseStdout
-- (";"," ")
-- 
-- >>> test ["-o\t", "-d,", "-O|"]
-- UseStdout
-- ("|","\t")
outputSpec :: forall m. (Functor m, Monad m)
           => CommonSeparators -> OptionParserT HawkOption m OutputSpec
outputSpec (r, f) = OutputSpec <$> sink <*> format
  where
    sink :: OptionParserT HawkOption m OutputSink
    sink = return UseStdout

    format :: OptionParserT HawkOption m OutputFormat
    format = OutputFormat <$> record <*> field

    record, field :: OptionParserT HawkOption m Delimiter
    record = fmap (fromMaybe r') $ consumeLast Option.OutputRecordDelimiter $ fromMaybe "" <$> Option.delimiterConsumer
    field  = fmap (fromMaybe f') $ consumeLast Option.OutputFieldDelimiter  $ fromMaybe "" <$> Option.delimiterConsumer

    r', f' :: Delimiter
    r' = fromSeparator r
    f' = fromSeparator f


-- | The information we need in order to evaluate a user expression:
--   the expression itself, and the context in which it should be evaluated.
--   In Hawk, that context is the user prelude.
-- 
-- >>> :{
-- let test = testP $ do { e <- exprSpec
--                       ; lift $ print $ untypedExpr e
--                       ; lift $ print $ userContextDirectory (contextSpec e)
--                       }
-- :}
-- 
-- >>> test []
-- error: missing user expression
-- *** Exception: ExitFailure 1
-- 
-- >>> test [""]
-- error: user expression cannot be empty
-- *** Exception: ExitFailure 1
--
-- >>> test ["-D;", "-d", "-a", "L.reverse","-c","somedir"]
-- "L.reverse"
-- "somedir"
exprSpec :: (Functor m, MonadIO m)
         => OptionParserT HawkOption m ExprSpec
exprSpec = ExprSpec <$> (ContextSpec <$> contextDir)
                    <*> expr
  where
    contextDir = do
      maybeDir <- consumeLast Option.ContextDirectory stringConsumer
      case maybeDir of
        Nothing -> liftIO findContextFromCurrDirOrDefault
        Just dir -> return dir
    expr = do
        r <- consumeExtra stringConsumer
        case r of
          Just e  -> if all isSpace e
                      then fail "user expression cannot be empty"
                      else return e
          Nothing -> fail "missing user expression"


-- | Parse command-line arguments to construct a `HawkSpec`.
-- 
-- TODO: complain if some arguments are unused (except perhaps "-d" and "-D").
-- 
-- >>> :{
-- let test args = do { spec <- runUncertainIO $ parseArgs args
--                    ; case spec of
--                        Help        -> putStrLn "Help"
--                        Version     -> putStrLn "Version"
--                        Eval  e   o -> putStrLn "Eval"  >> print (untypedExpr e)                                         >> print (recordDelimiter (outputFormat o), fieldDelimiter (outputFormat o))
--                        Apply e i o -> putStrLn "Apply" >> print (untypedExpr e, inputSource i) >> print (inputFormat i) >> print (recordDelimiter (outputFormat o), fieldDelimiter (outputFormat o))
--                        Map   e i o -> putStrLn "Map"   >> print (untypedExpr e, inputSource i) >> print (inputFormat i) >> print (recordDelimiter (outputFormat o), fieldDelimiter (outputFormat o))
--                    }
-- :}
-- 
-- >>> test []
-- Help
-- 
-- >>> test ["--help"]
-- Help
-- 
-- >>> test ["--version"]
-- Version
-- 
-- >>> test ["-d\\t", "L.head"]
-- Eval
-- "L.head"
-- ("\n","\t")
-- 
-- >>> test ["-D\r\n", "-d\\t", "-m", "L.head"]
-- Map
-- ("L.head",UseStdin)
-- Records (Delimiter "\r\n") (Fields (Delimiter "\t"))
-- ("\r\n","\t")
-- 
-- TODO: why is this test failing?
-- -->>> test ["-D", "-O\n", "-m", "L.head", "file.in"]
-- --Map
-- --("L.head",InputFile "file.in")
-- --RawStream
-- --("\n"," ")
parseArgs :: (Functor m,MonadIO m) => [String] -> UncertainT m HawkSpec
parseArgs [] = return Help
parseArgs args = runOptionParserT options parser args
  where
    parser = do
        lift $ return ()  -- silence a warning
        cmd <- fromMaybe eval <$> consumeExclusive assoc
        c <- commonSeparators
        cmd c
    assoc = [ (Option.Help,    help)
            , (Option.Version, version)
            , (Option.Apply,   apply)
            , (Option.Map,     map')
            ]
    
    help, version, eval, apply, map' :: (Functor m,MonadIO m) => CommonSeparators
                                     -> OptionParserT HawkOption m HawkSpec
    help    _ = return Help
    version _ = return Version
    eval    c = Eval  <$> exprSpec <*>                 outputSpec c
    apply   c = Apply <$> exprSpec <*> inputSpec c <*> outputSpec c
    map'    c = Map   <$> exprSpec <*> inputSpec c <*> outputSpec c
