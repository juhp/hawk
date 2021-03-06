{-# LANGUAGE OverloadedStrings #-}
-- | The string-typed version of Hawk's command-line arguments.
module System.Console.Hawk.Args.Option where

import Data.ByteString (ByteString)
import Data.ByteString.Char8 (pack)
import Text.Printf

import Control.Monad.Trans.OptionParser


data HawkOption
    = Apply
    | Map
    | FieldDelimiter
    | RecordDelimiter
    | OutputFieldDelimiter
    | OutputRecordDelimiter
    | Version
    | Help
    | ContextDirectory
  deriving (Show, Eq, Enum, Bounded)

-- | In the order listed by --help.
options :: [HawkOption]
options = enumFrom minBound


delimiter :: OptionType
delimiter = optional (Setting "delim")

-- | Interpret escape sequences, but don't worry if they're invalid.
-- 
-- >>> parseDelimiter ","
-- ","
-- 
-- >>> parseDelimiter "\\n"
-- "\n"
-- 
-- >>> parseDelimiter "\\t"
-- "\t"
-- 
-- >>> parseDelimiter "\\"
-- "\\"
parseDelimiter :: String -> ByteString
parseDelimiter s = pack $ case reads (printf "\"%s\"" s) of
    [(s', "")] -> s'
    _          -> s

-- | Almost like a string, except escape sequences are interpreted.
delimiterConsumer :: (Functor m, Monad m) => OptionConsumerT m (Maybe ByteString)
delimiterConsumer = fmap parseDelimiter <$> optionalConsumer stringConsumer

instance Option HawkOption where
  shortName Apply                 = 'a'
  shortName Map                   = 'm'
  shortName FieldDelimiter        = 'd'
  shortName RecordDelimiter       = 'D'
  shortName OutputFieldDelimiter  = 'o'
  shortName OutputRecordDelimiter = 'O'
  shortName Version               = 'v'
  shortName Help                  = 'h'
  shortName ContextDirectory      = 'c'
  
  longName Apply                 = "apply"
  longName Map                   = "map"
  longName FieldDelimiter        = "field-delimiter"
  longName RecordDelimiter       = "record-delimiter"
  longName OutputFieldDelimiter  = "output-field-delim"
  longName OutputRecordDelimiter = "output-record-delim"
  longName Version               = "version"
  longName Help                  = "help"
  longName ContextDirectory      = "context-directory"
  
  helpMsg Apply                      = ["apply <expr> to the entire table"]
  helpMsg Map                        = ["apply <expr> to each row"]
  helpMsg FieldDelimiter             = ["default whitespace"]
  helpMsg RecordDelimiter            = ["default '\\n'"]
  helpMsg OutputFieldDelimiter       = ["default <field-delim>"]
  helpMsg OutputRecordDelimiter      = ["default <record-delim>"]
  helpMsg Version                    = ["print version and exit"]
  helpMsg Help                       = ["this help"]
  helpMsg ContextDirectory           = ["<ctx-dir> directory, default is"
                                       ,"'~/.hawk'"]
  
  optionType Apply                 = flag
  optionType Map                   = flag
  optionType FieldDelimiter        = delimiter
  optionType RecordDelimiter       = delimiter
  optionType OutputFieldDelimiter  = delimiter
  optionType OutputRecordDelimiter = delimiter
  optionType Version               = flag
  optionType Help                  = flag
  optionType ContextDirectory      = filePath
