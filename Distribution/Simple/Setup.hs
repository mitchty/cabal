-----------------------------------------------------------------------------
-- |
-- Module      :  Distribution.Simple.Setup
-- Copyright   :  Isaac Jones 2003-2004
-- 
-- Maintainer  :  Isaac Jones <ijones@syntaxpolice.org>
-- Stability   :  alpha
-- Portability :  portable
--
-- Explanation: Data types and parser for the standard command-line
-- setup.  Will also return commands it doesn't know about.

{- All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.

    * Neither the name of Isaac Jones nor the names of other
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. -}

module Distribution.Simple.Setup (

  module Distribution.Simple.Compiler,

  GlobalFlags(..),   emptyGlobalFlags,   defaultGlobalFlags,   globalCommand,
  ConfigFlags(..),   emptyConfigFlags,   defaultConfigFlags,   configureCommand,
  CopyFlags(..),     emptyCopyFlags,     defaultCopyFlags,     copyCommand,
  InstallFlags(..),  emptyInstallFlags,  defaultInstallFlags,  installCommand,
  HaddockFlags(..),  emptyHaddockFlags,  defaultHaddockFlags,  haddockCommand,
  HscolourFlags(..), emptyHscolourFlags, defaultHscolourFlags, hscolourCommand,
  BuildFlags(..),    emptyBuildFlags,    defaultBuildFlags,    buildCommand,
  CleanFlags(..),    emptyCleanFlags,    defaultCleanFlags,    cleanCommand,
  PFEFlags(..),      emptyPFEFlags,      defaultPFEFlags,      programaticaCommand,
  MakefileFlags(..), emptyMakefileFlags, defaultMakefileFlags, makefileCommand,
  RegisterFlags(..), emptyRegisterFlags, defaultRegisterFlags, registerCommand,
                                                               unregisterCommand,
  SDistFlags(..),    emptySDistFlags,    defaultSDistFlags,    sdistCommand,
                                                               testCommand,
  CopyDest(..),
  configureArgs,

  Flag(..),
  toFlag,
  fromFlag,
  fromFlagOrDefault,
  flagToMaybe,
  flagToList,
                           ) where

import Distribution.Simple.Command
import Distribution.Simple.Compiler (CompilerFlavor(..), Compiler(..),
                                     defaultCompilerFlavor, PackageDB(..))
import Distribution.Simple.Utils (wrapText)
import Distribution.Simple.Program (Program(..), ProgramConfiguration,
                             knownPrograms)
import Distribution.Simple.InstallDirs
         ( InstallDirs(..), CopyDest(..),
           PathTemplate, toPathTemplate, fromPathTemplate )
import Data.List (sort)
import Data.Char( toLower, isSpace )
import Data.Monoid (Monoid(..))
import Distribution.Verbosity

-- ------------------------------------------------------------
-- * Flag type
-- ------------------------------------------------------------

-- | All flags are monoids, they come in two flavours:
--
-- 1. list flags eg
--
-- > --ghc-option=foo --ghc-option=bar
--
-- gives us all the values ["foo", "bar"]
--
-- 2. singular value flags, eg:
--
-- > --enable-foo --disable-foo
--
-- gives us Just False
-- So this Flag type is for the latter singular kind of flag.
-- Its monoid instance gives us the behaviour where it starts out as
-- 'NoFlag' and later flags override earlier ones.
--
data Flag a = Flag a | NoFlag deriving Show

instance Functor Flag where
  fmap f (Flag x) = Flag (f x)
  fmap _ NoFlag  = NoFlag

instance Monoid (Flag a) where
  mempty = NoFlag
  _ `mappend` f@(Flag _) = f
  f `mappend` NoFlag    = f

toFlag :: a -> Flag a
toFlag = Flag

fromFlag :: Flag a -> a
fromFlag (Flag x) = x
fromFlag NoFlag   = error "fromFlag NoFlag. Use fromFlagOrDefault"

fromFlagOrDefault :: a -> Flag a -> a
fromFlagOrDefault _   (Flag x) = x
fromFlagOrDefault def NoFlag   = def

flagToMaybe :: Flag a -> Maybe a
flagToMaybe (Flag x) = Just x
flagToMaybe NoFlag   = Nothing

flagToList :: Flag a -> [a]
flagToList (Flag x) = [x]
flagToList NoFlag   = []

-- ------------------------------------------------------------
-- * Global flags
-- ------------------------------------------------------------

-- In fact since individual flags types are monoids and these are just sets of
-- flags then they are also monoids pointwise. This turns out to be really
-- useful. The mempty is the set of empty flags and mappend allows us to
-- override specific flags. For example we can start with default flags and
-- override with the ones we get from a file or the command line, or both.

-- | Flags that apply at the top level, not to any sub-command.
data GlobalFlags = GlobalFlags {
    globalVersion        :: Flag Bool,
    globalNumericVersion :: Flag Bool
  }

defaultGlobalFlags :: GlobalFlags
defaultGlobalFlags  = GlobalFlags {
    globalVersion        = Flag False,
    globalNumericVersion = Flag False
  }

globalCommand :: CommandUI GlobalFlags
globalCommand = makeCommand name shortDesc longDesc defaultGlobalFlags options
  where
    name       = ""
    shortDesc  = ""
    longDesc   = Just $ \pname ->
         "Typical steps for installing Cabal packages:\n"
      ++ unlines [ "  " ++ pname ++ " " ++ x
                 | x <- ["configure", "build", "install"]]
      ++ "\nFor more information about a command, try '"
          ++ pname ++ " COMMAND --help'."
      ++ "\nThis Setup program uses the Haskell Cabal Infrastructure."
      ++ "\nSee http://www.haskell.org/cabal/ for more information.\n"
    options _  =
      [option ['V'] ["version"]
         "Print version information"
         globalVersion (\v flags -> flags { globalVersion = v })
         trueArg
      ,option [] ["numeric-version"]
         "Print just the version number"
         globalNumericVersion (\v flags -> flags { globalNumericVersion = v })
         trueArg
      ]

emptyGlobalFlags :: GlobalFlags
emptyGlobalFlags = mempty

instance Monoid GlobalFlags where
  mempty = GlobalFlags {
    globalVersion        = mempty,
    globalNumericVersion = mempty
  }
  mappend a b = GlobalFlags {
    globalVersion        = combine globalVersion,
    globalNumericVersion = combine globalNumericVersion
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Config flags
-- ------------------------------------------------------------

-- | Flags to @configure@ command
data ConfigFlags = ConfigFlags {
    --FIXME: the configPrograms is only here to pass info through to configure
    -- because the type of configure is constrained by the UserHooks.
    -- when we change UserHooks next we should pass the initial
    -- ProgramConfiguration directly and not via ConfigFlags
    configPrograms      :: ProgramConfiguration, -- ^All programs that cabal may run

    configProgramPaths  :: [(String, FilePath)], -- ^user specifed programs paths
    configProgramArgs   :: [(String, [String])], -- ^user specifed programs args
    configHcFlavor      :: Flag CompilerFlavor, -- ^The \"flavor\" of the compiler, sugh as GHC or Hugs.
    configHcPath        :: Flag FilePath, -- ^given compiler location
    configHcPkg         :: Flag FilePath, -- ^given hc-pkg location
    configVanillaLib    :: Flag Bool,     -- ^Enable vanilla library
    configProfLib       :: Flag Bool,     -- ^Enable profiling in the library
    configSharedLib     :: Flag Bool,     -- ^Build shared library
    configProfExe       :: Flag Bool,     -- ^Enable profiling in the executables.
    configConfigureArgs :: [String],      -- ^Extra arguments to @configure@
    configOptimization  :: Flag Bool,     -- ^Enable optimization.
    configInstallDirs   :: InstallDirs (Flag PathTemplate), -- ^Installation paths
    configScratchDir    :: Flag FilePath,

    configVerbose   :: Flag Verbosity, -- ^verbosity level
    configUserInstall :: Flag Bool,    -- ^The --user/--global flag
    configPackageDB :: Flag PackageDB, -- ^Which package DB to use
    configGHCiLib   :: Flag Bool,      -- ^Enable compiling library for GHCi
    configSplitObjs :: Flag Bool,      -- ^Enable -split-objs with GHC
    configConfigurationsFlags :: [(String, Bool)]
  }
  deriving Show

defaultConfigFlags :: ProgramConfiguration -> ConfigFlags
defaultConfigFlags progConf = emptyConfigFlags {
    configPrograms     = progConf,
    configHcFlavor     = maybe NoFlag Flag defaultCompilerFlavor,
    configVanillaLib   = Flag True,
    configProfLib      = Flag False,
    configSharedLib    = Flag False,
    configProfExe      = Flag False,
    configOptimization = Flag True,
    configVerbose      = Flag normal,
    configUserInstall  = Flag False,           --TODO: reverse this
    configGHCiLib      = Flag True,
    configSplitObjs    = Flag False -- takes longer, so turn off by default
  }

configureCommand :: ProgramConfiguration -> CommandUI ConfigFlags
configureCommand progConf = makeCommand name shortDesc longDesc defaultFlags options
  where
    name       = "configure"
    shortDesc  = "Prepare to build the package."
    longDesc   = Just (\_ -> programFlagsDescription progConf)
    defaultFlags = defaultConfigFlags progConf
    options showOrParseArgs =
      [optionVerbose configVerbose (\v flags -> flags { configVerbose = v })

      ,option "g" ["ghc"]
         "compile with GHC"
         configHcFlavor (\v flags -> flags { configHcFlavor = v })
         (noArg (Flag GHC) (\f -> case f of Flag GHC -> True; _ -> False))

      ,option "" ["nhc98"]
         "compile with NHC"
         configHcFlavor (\v flags -> flags { configHcFlavor = v })
         (noArg (Flag NHC) (\f -> case f of Flag NHC -> True; _ -> False))

      ,option "" ["jhc"]
         "compile with JHC"
         configHcFlavor (\v flags -> flags { configHcFlavor = v })
         (noArg (Flag JHC) (\f -> case f of Flag JHC -> True; _ -> False))

      ,option "" ["hugs"]
         "compile with hugs"
         configHcFlavor (\v flags -> flags { configHcFlavor = v })
         (noArg (Flag Hugs) (\f -> case f of Flag Hugs -> True; _ -> False))

      ,option "w" ["with-compiler"]
         "give the path to a particular compiler"
         configHcPath (\v flags -> flags { configHcPath = v })
         (reqArgFlag "PATH")

      ,option "" ["with-hc-pkg"]
         "give the path to the package tool"
         configHcPkg (\v flags -> flags { configHcPkg = v })
         (reqArgFlag "PATH")

      ,option "" ["prefix"]
         "bake this prefix in preparation of installation"
         prefix (\v flags -> flags { prefix = v })
         installDirArg

      ,option "" ["bindir"]
         "installation directory for executables"
         bindir (\v flags -> flags { bindir = v })
         installDirArg

      ,option "" ["libdir"]
         "installation directory for libraries"
         libdir (\v flags -> flags { libdir = v })
         installDirArg

      ,option "" ["libsubdir"]
	 "subdirectory of libdir in which libs are installed"
         libsubdir (\v flags -> flags { libsubdir = v })
         installDirArg

      ,option "" ["libexecdir"]
	 "installation directory for program executables"
         libexecdir (\v flags -> flags { libexecdir = v })
         installDirArg

      ,option "" ["datadir"]
	 "installation directory for read-only data"
         datadir (\v flags -> flags { datadir = v })
         installDirArg

      ,option "" ["datasubdir"]
	 "subdirectory of datadir in which data files are installed"
         datasubdir (\v flags -> flags { datasubdir = v })
         installDirArg

      ,option "" ["docdir"]
	 "installation directory for documentation"
         docdir (\v flags -> flags { docdir = v })
         installDirArg

      ,option "" ["htmldir"]
	 "installation directory for HTML documentation"
         htmldir (\v flags -> flags { htmldir = v })
         installDirArg

      ,option "" ["haddockdir"]
	 "installation directory for haddock interfaces"
         haddockdir (\v flags -> flags { haddockdir = v })
         installDirArg

      ,option "b" ["scratchdir"]
         "directory to receive the built package [dist/scratch]"
         configScratchDir (\v flags -> flags { configScratchDir = v })
         (reqArgFlag "DIR")

      ,option "" ["enable-library-vanilla"]
         "Enable vanilla libraries"
         configVanillaLib (\v flags -> flags { configVanillaLib = v })
         trueArg

      ,option "" ["disable-library-vanilla"]
         "Disable vanilla libraries"
          configVanillaLib (\v flags -> flags { configVanillaLib = v })
          falseArg

      ,option "p" ["enable-library-profiling"]
         "Enable library profiling"
         configProfLib (\v flags -> flags { configProfLib = v })
         trueArg

      ,option "" ["disable-library-profiling"]
         "Disable library profiling"
         configProfLib (\v flags -> flags { configProfLib = v })
         falseArg

      ,option "" ["enable-shared"]
         "Enable shared library"
         configSharedLib (\v flags -> flags { configSharedLib = v })
         trueArg

      ,option "" ["disable-shared"]
         "Disable shared library"
         configSharedLib (\v flags -> flags { configSharedLib = v })
         falseArg

      ,option "" ["enable-executable-profiling"]
         "Enable executable profiling"
         configProfExe (\v flags -> flags { configProfExe = v })
         trueArg

      ,option "" ["disable-executable-profiling"]
         "Disable executable profiling"
         configProfExe (\v flags -> flags { configProfExe = v })
         falseArg

      ,option "O" ("enable-optimization": case showOrParseArgs of
                      -- Allow British English spelling:
                      ShowArgs -> []; ParseArgs -> ["enable-optimisation"])
         "Build with optimization"
         configOptimization (\v flags -> flags { configOptimization = v })
         trueArg

      ,option "" ("disable-optimization": case showOrParseArgs of
                      -- Allow British English spelling:
                      ShowArgs -> []; ParseArgs -> ["disable-optimisation"])
         "Build without optimization"
         configOptimization (\v flags -> flags { configOptimization = v })
         falseArg

      ,option "" ["enable-library-for-ghci"]
         "compile library for use with GHCi"
         configGHCiLib (\v flags -> flags { configGHCiLib = v })
         trueArg

      ,option "" ["disable-library-for-ghci"]
         "do not compile libraries for GHCi"
         configGHCiLib (\v flags -> flags { configGHCiLib = v })
         falseArg

      ,option "" ["enable-split-objs"]
         "split library into smaller objects to reduce binary sizes (GHC 6.6+)"
         configSplitObjs (\v flags -> flags { configSplitObjs = v })
         trueArg

      ,option "" ["disable-split-objs"]
         "split library into smaller objects to reduce binary sizes (GHC 6.6+)"
         configSplitObjs (\v flags -> flags { configSplitObjs = v })
         falseArg

      ,option "" ["configure-option"]
         "Extra option for configure"
         configConfigureArgs (\v flags -> flags { configConfigureArgs = v })
         (reqArg "OPT" (\x -> [x]) id)

      ,option "" ["user"]
         "do a per-user installation"
         configUserInstall (\v flags -> flags { configUserInstall = v })
         trueArg

      ,option "" ["global"]
         "(default) do a system-wide installation"
         configUserInstall (\v flags -> flags { configUserInstall = v })
         falseArg

      ,option "" ["package-db"]
         "Use a specific package database (to satisfy dependencies and register in)"
         configPackageDB (\v flags -> flags { configPackageDB = v })
         (reqArg "PATH" (Flag . SpecificPackageDB)
                        (\f -> case f of
                                 Flag (SpecificPackageDB db) -> [db]
                                 _ -> []))

      ,option "f" ["flags"]
         "Force values for the given flags in Cabal conditionals in the .cabal file.  E.g., --flags=\"debug -usebytestrings\" forces the flag \"debug\" to true and \"usebytestrings\" to false."
         configConfigurationsFlags (\v flags -> flags { configConfigurationsFlags = v })
         (reqArg "FLAGS" readFlagList showFlagList)

      ]
      ++ programConfigurationPaths   progConf showOrParseArgs
           configProgramPaths (\v fs -> fs { configProgramPaths = v })
      ++ programConfigurationOptions progConf showOrParseArgs
           configProgramArgs (\v fs -> fs { configProgramArgs = v })

    readFlagList :: String -> [(String, Bool)]
    readFlagList = map tagWithValue . words
      where tagWithValue ('-':fname) = (map toLower fname, False)
            tagWithValue fname       = (map toLower fname, True)
    
    showFlagList :: [(String, Bool)] -> [String]
    showFlagList fs = [ if not set then '-':fname else fname | (fname, set) <- fs]

    installDirArg get set = reqArgFlag "DIR"
      (fmap fromPathTemplate.get.configInstallDirs)
      (\v flags -> flags { configInstallDirs =
                             set (fmap toPathTemplate v) (configInstallDirs flags)})

emptyConfigFlags :: ConfigFlags
emptyConfigFlags = mempty

instance Monoid ConfigFlags where
  mempty = ConfigFlags {
    configPrograms      = error "FIXME: remove configPrograms",
    configProgramPaths  = mempty,
    configProgramArgs   = mempty,
    configHcFlavor      = mempty,
    configHcPath        = mempty,
    configHcPkg         = mempty,
    configVanillaLib    = mempty,
    configProfLib       = mempty,
    configSharedLib     = mempty,
    configProfExe       = mempty,
    configConfigureArgs = mempty,
    configOptimization  = mempty,
    configInstallDirs   = mempty,
    configScratchDir    = mempty,
    configVerbose       = mempty,
    configUserInstall   = mempty,
    configPackageDB     = mempty,
    configGHCiLib       = mempty,
    configSplitObjs     = mempty,
    configConfigurationsFlags = mempty
  }
  mappend a b =  ConfigFlags {
    configPrograms      = configPrograms b,
    configProgramPaths  = combine configProgramPaths,
    configProgramArgs   = combine configProgramArgs,
    configHcFlavor      = combine configHcFlavor,
    configHcPath        = combine configHcPath,
    configHcPkg         = combine configHcPkg,
    configVanillaLib    = combine configVanillaLib,
    configProfLib       = combine configProfLib,
    configSharedLib     = combine configSharedLib,
    configProfExe       = combine configProfExe,
    configConfigureArgs = combine configConfigureArgs,
    configOptimization  = combine configOptimization,
    configInstallDirs   = combine configInstallDirs,
    configScratchDir    = combine configScratchDir,
    configVerbose       = combine configVerbose,
    configUserInstall   = combine configUserInstall,
    configPackageDB     = combine configPackageDB,
    configGHCiLib       = combine configGHCiLib,
    configSplitObjs     = combine configSplitObjs,
    configConfigurationsFlags = combine configConfigurationsFlags
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Copy flags
-- ------------------------------------------------------------

-- | Flags to @copy@: (destdir, copy-prefix (backwards compat), verbosity)
data CopyFlags = CopyFlags {
    copyDest    :: Flag CopyDest,
    copyVerbose :: Flag Verbosity
  }
  deriving Show

defaultCopyFlags :: CopyFlags
defaultCopyFlags  = CopyFlags {
    copyDest    = Flag NoCopyDest,
    copyVerbose = Flag normal
  }

copyCommand :: CommandUI CopyFlags
copyCommand = makeCommand name shortDesc longDesc defaultCopyFlags options
  where
    name       = "copy"
    shortDesc  = "Copy the files into the install locations."
    longDesc   = Just $ \_ ->
          "Does not call register, and allows a prefix at install time\n"
       ++ "Without the --destdir flag, configure determines location.\n"
    options _  =
      [optionVerbose copyVerbose (\v flags -> flags { copyVerbose = v })

      ,option "" ["destdir"]
         "directory to copy files to, prepended to installation directories"
         copyDest (\v flags -> flags { copyDest = v })
         (reqArg "DIR" (Flag . CopyTo)
                       (\f -> case f of Flag (CopyTo p) -> [p]; _ -> []))

      ,option "" ["copy-prefix"]
         "[DEPRECATED, directory to copy files to instead of prefix]"
         copyDest (\v flags -> flags { copyDest = v })
         (reqArg "DIR" (Flag . CopyPrefix)
                       (\f -> case f of Flag (CopyPrefix p) -> [p]; _ -> []))

      ]

emptyCopyFlags :: CopyFlags
emptyCopyFlags = mempty

instance Monoid CopyFlags where
  mempty = CopyFlags {
    copyDest    = mempty,
    copyVerbose = mempty
  }
  mappend a b = CopyFlags {
    copyDest    = combine copyDest,
    copyVerbose = combine copyVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Install flags
-- ------------------------------------------------------------

-- | Flags to @install@: (package db, verbosity)
data InstallFlags = InstallFlags {
    installPackageDB :: Flag PackageDB,
    installVerbose   :: Flag Verbosity
  }
  deriving Show

defaultInstallFlags :: InstallFlags
defaultInstallFlags  = InstallFlags {
    installPackageDB = NoFlag,
    installVerbose   = Flag normal
  }

installCommand :: CommandUI InstallFlags
installCommand = makeCommand name shortDesc longDesc defaultInstallFlags options
  where
    name       = "install"
    shortDesc  = "Copy the files into the install locations. Run register."
    longDesc   = Just $ \_ ->
         "Unlike the copy command, install calls the register command.\n"
      ++ "If you want to install into a location that is not what was\n"
      ++ "specified in the configure step, use the copy command.\n"
    options _  =
      [optionVerbose installVerbose (\v flags -> flags { installVerbose = v })

      ,option "" ["user"]
         "upon registration, register this package in the user's local package database"
         installPackageDB (\v flags -> flags { installPackageDB = v })
         (noArg (Flag UserPackageDB)
                (\f -> case f of Flag UserPackageDB -> True; _ -> False))

      ,option "" ["global"]
         "(default; override with configure) upon registration, register this package in the system-wide package database"
         installPackageDB (\v flags -> flags { installPackageDB = v })
         (noArg (Flag GlobalPackageDB)
                (\f -> case f of Flag GlobalPackageDB -> True; _ -> False))

      ]

emptyInstallFlags :: InstallFlags
emptyInstallFlags = mempty

instance Monoid InstallFlags where
  mempty = InstallFlags{
    installPackageDB = mempty,
    installVerbose   = mempty
  }
  mappend a b = InstallFlags{
    installPackageDB = combine installPackageDB,
    installVerbose   = combine installVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * SDist flags
-- ------------------------------------------------------------

-- | Flags to @sdist@: (snapshot, verbosity)
data SDistFlags = SDistFlags {
    sDistSnapshot :: Flag Bool,
    sDistVerbose  :: Flag Verbosity
  }
  deriving Show

defaultSDistFlags :: SDistFlags
defaultSDistFlags = SDistFlags {
    sDistSnapshot = Flag False,
    sDistVerbose  = Flag normal
  }

sdistCommand :: CommandUI SDistFlags
sdistCommand = makeCommand name shortDesc longDesc defaultSDistFlags options
  where
    name       = "sdist"
    shortDesc  = "Generate a source distribution file (.tar.gz)."
    longDesc   = Nothing
    options _  =
      [optionVerbose sDistVerbose (\v flags -> flags { sDistVerbose = v })

      ,option "" ["snapshot"]
         "Produce a snapshot source distribution"
         sDistSnapshot (\v flags -> flags { sDistSnapshot = v })
         trueArg
      ]

emptySDistFlags :: SDistFlags
emptySDistFlags = mempty

instance Monoid SDistFlags where
  mempty = SDistFlags {
    sDistSnapshot = mempty,
    sDistVerbose  = mempty
  }
  mappend a b = SDistFlags {
    sDistSnapshot = combine sDistSnapshot,
    sDistVerbose  = combine sDistVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Register flags
-- ------------------------------------------------------------

-- | Flags to @register@ and @unregister@: (user package, gen-script,
-- in-place, verbosity)
data RegisterFlags = RegisterFlags {
    regPackageDB   :: Flag PackageDB,
    regGenScript   :: Flag Bool,
    regGenPkgConf  :: Flag (Maybe FilePath),
    regInPlace     :: Flag Bool,
    regVerbose     :: Flag Verbosity
  }
  deriving Show

defaultRegisterFlags :: RegisterFlags
defaultRegisterFlags = RegisterFlags {
    regPackageDB   = NoFlag,
    regGenScript   = Flag False,
    regGenPkgConf  = Flag Nothing,
    regInPlace     = Flag False,
    regVerbose     = Flag normal
  }

registerCommand :: CommandUI RegisterFlags
registerCommand = makeCommand name shortDesc longDesc defaultRegisterFlags options
  where
    name       = "register"
    shortDesc  = "Register this package with the compiler."
    longDesc   = Nothing
    options _  =
      [optionVerbose regVerbose (\v flags -> flags { regVerbose = v })

      ,option "" ["user"]
         "upon registration, register this package in the user's local package database"
         regPackageDB (\v flags -> flags { regPackageDB = v })
         (noArg (Flag UserPackageDB)
                (\f -> case f of Flag UserPackageDB -> True; _ -> False))

      ,option "" ["global"]
         "(default) upon registration, register this package in the system-wide package database"
         regPackageDB (\v flags -> flags { regPackageDB = v })
         (noArg (Flag GlobalPackageDB)
                (\f -> case f of Flag GlobalPackageDB -> True; _ -> False))

      ,option "" ["inplace"]
         "register the package in the build location, so it can be used without being installed"
         regInPlace (\v flags -> flags { regInPlace = v })
         trueArg

      ,option "" ["gen-script"]
         "instead of registering, generate a script to register later"
         regGenScript (\v flags -> flags { regGenScript = v })
         trueArg

      ,option "" ["gen-pkg-config"]
         "instead of registering, generate a package registration file"
         regGenPkgConf (\v flags -> flags { regGenPkgConf  = v })
         (optArg "PKG" Flag flagToList)
      ]

unregisterCommand :: CommandUI RegisterFlags
unregisterCommand = makeCommand name shortDesc longDesc defaultRegisterFlags options
  where
    name       = "unregister"
    shortDesc  = "Unregister this package with the compiler."
    longDesc   = Nothing
    options _  =
      [optionVerbose regVerbose (\v flags -> flags { regVerbose = v })

      ,option "" ["user"]
         "unregister this package in the user's local package database"
         regPackageDB (\v flags -> flags { regPackageDB = v })
         (noArg (Flag UserPackageDB)
                (\f -> case f of Flag UserPackageDB -> True; _ -> False))

      ,option "" ["global"]
         "(default) unregister this package in the system-wide package database"
         regPackageDB (\v flags -> flags { regPackageDB = v })
         (noArg (Flag GlobalPackageDB)
                (\f -> case f of Flag GlobalPackageDB -> True; _ -> False))

      ,option "" ["gen-script"]
         "Instead of performing the unregister command, generate a script to unregister later"
         regGenScript (\v flags -> flags { regGenScript = v })
         trueArg
      ]

emptyRegisterFlags :: RegisterFlags
emptyRegisterFlags = mempty

instance Monoid RegisterFlags where
  mempty = RegisterFlags {
    regPackageDB   = mempty,
    regGenScript   = mempty,
    regGenPkgConf  = mempty,
    regInPlace     = mempty,
    regVerbose     = mempty
  }
  mappend a b = RegisterFlags {
    regPackageDB   = combine regPackageDB,
    regGenScript   = combine regGenScript,
    regGenPkgConf  = combine regGenPkgConf,
    regInPlace     = combine regInPlace,
    regVerbose     = combine regVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * HsColour flags
-- ------------------------------------------------------------

data HscolourFlags = HscolourFlags {
    hscolourCSS         :: Flag FilePath,
    hscolourExecutables :: Flag Bool,
    hscolourVerbose     :: Flag Verbosity
  }
  deriving Show

emptyHscolourFlags :: HscolourFlags
emptyHscolourFlags = mempty

defaultHscolourFlags :: HscolourFlags
defaultHscolourFlags = HscolourFlags {
    hscolourCSS         = NoFlag,
    hscolourExecutables = Flag False,
    hscolourVerbose     = Flag normal
  }

instance Monoid HscolourFlags where
  mempty = HscolourFlags {
    hscolourCSS         = mempty,
    hscolourExecutables = mempty,
    hscolourVerbose     = mempty
  }
  mappend a b = HscolourFlags {
    hscolourCSS         = combine hscolourCSS,
    hscolourExecutables = combine hscolourExecutables,
    hscolourVerbose     = combine hscolourVerbose
  }
    where combine field = field a `mappend` field b

hscolourCommand :: CommandUI HscolourFlags
hscolourCommand = makeCommand name shortDesc longDesc defaultHscolourFlags options
  where
    name       = "hscolour"
    shortDesc  = "Generate HsColour colourised code, in HTML format."
    longDesc   = Just (\_ -> "Requires hscolour.")
    options _  =
      [optionVerbose hscolourVerbose (\v flags -> flags { hscolourVerbose = v })

      ,option "" ["executables"]
         "Run hscolour for Executables targets"
         hscolourExecutables (\v flags -> flags { hscolourExecutables = v })
         trueArg

      ,option "" ["css"]
         "Use a cascading style sheet"
         hscolourCSS (\v flags -> flags { hscolourCSS = v })
         (reqArgFlag "PATH")
      ]

-- ------------------------------------------------------------
-- * Haddock flags
-- ------------------------------------------------------------

data HaddockFlags = HaddockFlags {
    haddockHoogle       :: Flag Bool,
    haddockHtmlLocation :: Flag String,
    haddockExecutables  :: Flag Bool,
    haddockCss          :: Flag FilePath,
    haddockHscolour     :: Flag Bool,
    haddockHscolourCss  :: Flag FilePath,
    haddockVerbose      :: Flag Verbosity
  }
  deriving Show

defaultHaddockFlags :: HaddockFlags
defaultHaddockFlags  = HaddockFlags {
    haddockHoogle       = Flag False,
    haddockHtmlLocation = NoFlag,
    haddockExecutables  = Flag False,
    haddockCss          = NoFlag,
    haddockHscolour     = Flag False,
    haddockHscolourCss  = NoFlag,
    haddockVerbose      = Flag normal
  }

haddockCommand :: CommandUI HaddockFlags
haddockCommand = makeCommand name shortDesc longDesc defaultHaddockFlags options
  where
    name       = "haddock"
    shortDesc  = "Generate Haddock HTML documentation."
    longDesc   = Just (\_ -> "Requires cpphs and haddock.\n")
    options _  =
      [optionVerbose haddockVerbose (\v flags -> flags { haddockVerbose = v })

      ,option "" ["hoogle"]
         "Generate a hoogle database"
         haddockHoogle (\v flags -> flags { haddockHoogle = v })
         trueArg

      ,option "" ["html-location"]
         "Location of HTML documentation for pre-requisite packages"
         haddockHtmlLocation (\v flags -> flags { haddockHtmlLocation = v })
         (reqArgFlag "URL")

      ,option "" ["executables"]
         "Run haddock for Executables targets"
         haddockExecutables (\v flags -> flags { haddockExecutables = v })
         trueArg

      ,option "" ["css"]
         "Use PATH as the haddock stylesheet"
         haddockCss (\v flags -> flags { haddockCss = v })
         (reqArgFlag "PATH")

      ,option "" ["hyperlink-source"]
         "Hyperlink the documentation to the source code (using HsColour)"
         haddockHscolour (\v flags -> flags { haddockHscolour = v })
         trueArg

      ,option "" ["hscolour-css"]
         "Use PATH as the HsColour stylesheet"
         haddockHscolourCss (\v flags -> flags { haddockHscolourCss = v })
         (reqArgFlag "PATH")
      ]

emptyHaddockFlags :: HaddockFlags
emptyHaddockFlags = mempty

instance Monoid HaddockFlags where
  mempty = HaddockFlags {
    haddockHoogle       = mempty,
    haddockHtmlLocation = mempty,
    haddockExecutables  = mempty,
    haddockCss          = mempty,
    haddockHscolour     = mempty,
    haddockHscolourCss  = mempty,
    haddockVerbose      = mempty
  }
  mappend a b = HaddockFlags {
    haddockHoogle       = combine haddockHoogle,
    haddockHtmlLocation = combine haddockHtmlLocation,
    haddockExecutables  = combine haddockExecutables,
    haddockCss          = combine haddockCss,
    haddockHscolour     = combine haddockHscolour,
    haddockHscolourCss  = combine haddockHscolourCss,
    haddockVerbose      = combine haddockVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Clean flags
-- ------------------------------------------------------------

data CleanFlags = CleanFlags {
    cleanSaveConf  :: Flag Bool,
    cleanVerbose   :: Flag Verbosity
  }
  deriving Show

defaultCleanFlags :: CleanFlags
defaultCleanFlags  = CleanFlags {
    cleanSaveConf = Flag False,
    cleanVerbose  = Flag normal
  }

cleanCommand :: CommandUI CleanFlags
cleanCommand = makeCommand name shortDesc longDesc defaultCleanFlags options
  where
    name       = "clean"
    shortDesc  = "Clean up after a build."
    longDesc   = Just (\_ -> "Removes .hi, .o, preprocessed sources, etc.\n")
    options _  =
      [optionVerbose cleanVerbose (\v flags -> flags { cleanVerbose = v })

      ,option "s" ["save-configure"]
         "Do not remove the configuration file (dist/setup-config) during cleaning.  Saves need to reconfigure."
         cleanSaveConf (\v flags -> flags { cleanSaveConf = v })
         trueArg
      ]

emptyCleanFlags :: CleanFlags
emptyCleanFlags = mempty

instance Monoid CleanFlags where
  mempty = CleanFlags {
    cleanSaveConf = mempty,
    cleanVerbose  = mempty
  }
  mappend a b = CleanFlags {
    cleanSaveConf = combine cleanSaveConf,
    cleanVerbose  = combine cleanVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Build flags
-- ------------------------------------------------------------

data BuildFlags = BuildFlags {
    buildProgramArgs :: [(String, [String])],
    buildVerbose     :: Flag Verbosity
  }
  deriving Show

defaultBuildFlags :: BuildFlags
defaultBuildFlags  = BuildFlags {
    buildProgramArgs = [],
    buildVerbose     = Flag normal
  }

buildCommand :: ProgramConfiguration -> CommandUI BuildFlags
buildCommand progConf = makeCommand name shortDesc longDesc defaultBuildFlags options
  where
    name       = "build"
    shortDesc  = "Make this package ready for installation."
    longDesc   = Nothing
    options showOrParseArgs =
      optionVerbose buildVerbose (\v flags -> flags { buildVerbose = v })

      : programConfigurationOptions progConf showOrParseArgs
          buildProgramArgs (\v flags -> flags { buildProgramArgs = v})

emptyBuildFlags :: BuildFlags
emptyBuildFlags = mempty

instance Monoid BuildFlags where
  mempty = BuildFlags {
    buildProgramArgs = mempty,
    buildVerbose     = mempty
  }
  mappend a b = BuildFlags {
    buildProgramArgs = combine buildProgramArgs,
    buildVerbose     = combine buildVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Makefile flags
-- ------------------------------------------------------------

data MakefileFlags = MakefileFlags {
    makefileFile    :: Flag FilePath,
    makefileVerbose :: Flag Verbosity
  }
  deriving Show

defaultMakefileFlags :: MakefileFlags
defaultMakefileFlags  = MakefileFlags {
    makefileFile    = NoFlag,
    makefileVerbose = Flag normal
  }

makefileCommand :: CommandUI MakefileFlags
makefileCommand = makeCommand name shortDesc longDesc defaultMakefileFlags options
  where
    name       = "makefile"
    shortDesc  = "Generate a makefile (only for GHC libraries)."
    longDesc   = Nothing
    options _  =
      [optionVerbose makefileVerbose (\v flags -> flags { makefileVerbose = v })

      ,option "f" ["file"]
         "Filename to use (default: Makefile)."
         makefileFile (\f flags -> flags { makefileFile = f })
         (reqArgFlag "PATH")
      ]

emptyMakefileFlags :: MakefileFlags
emptyMakefileFlags  = mempty

instance Monoid MakefileFlags where
  mempty = MakefileFlags {
    makefileFile    = mempty,
    makefileVerbose = mempty
  }
  mappend a b = MakefileFlags {
    makefileFile    = combine makefileFile,
    makefileVerbose = combine makefileVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Programatica flags
-- ------------------------------------------------------------

data PFEFlags = PFEFlags {
    pfeVerbose :: Flag Verbosity
  }
  deriving Show

defaultPFEFlags :: PFEFlags
defaultPFEFlags = PFEFlags {
    pfeVerbose = Flag normal
  }

programaticaCommand :: CommandUI PFEFlags
programaticaCommand = makeCommand name shortDesc longDesc defaultPFEFlags options
  where
    name       = "pfe"
    shortDesc  = "Generate Programatica Project."
    longDesc   = Nothing
    options _  =
      [optionVerbose pfeVerbose (\v flags -> flags { pfeVerbose = v })
      ]

emptyPFEFlags :: PFEFlags
emptyPFEFlags = mempty

instance Monoid PFEFlags where
  mempty = PFEFlags {
    pfeVerbose = mempty
  }
  mappend a b = PFEFlags {
    pfeVerbose = combine pfeVerbose
  }
    where combine field = field a `mappend` field b

-- ------------------------------------------------------------
-- * Test flags
-- ------------------------------------------------------------

testCommand :: CommandUI ()
testCommand = makeCommand name shortDesc longDesc () options
  where
    name       = "test"
    shortDesc  = "Run the test suite, if any (configure with UserHooks)."
    longDesc   = Nothing
    options _  = []

-- ------------------------------------------------------------
-- * Shared options utils
-- ------------------------------------------------------------

programFlagsDescription :: ProgramConfiguration -> String
programFlagsDescription progConf =
     "The flags --with-PROG and --PROG-option(s) can be used with"
  ++ " the following programs:"
  ++ (concatMap ("\n  "++) . wrapText 77 . sort)
     [ programName prog | (prog, _) <- knownPrograms progConf ]
  ++ "\n"

programConfigurationPaths
  :: ProgramConfiguration
  -> ShowOrParseArgs
  -> (flags -> [(String, FilePath)])
  -> ([(String, FilePath)] -> (flags -> flags))
  -> [Option flags]
programConfigurationPaths progConf showOrParseArgs get set =
  case showOrParseArgs of
    -- we don't want a verbose help text list so we just show a generic one:
    ShowArgs  -> [withProgramPath "PROG"]
    ParseArgs -> map (withProgramPath . programName . fst) (knownPrograms progConf)
  where
    withProgramPath prog =
      option "" ["with-" ++ prog]
        ("give the path to " ++ prog)
        get set
        (reqArg "PATH" (\path -> [(prog, path)])
          (\progPaths -> [ path | (prog', path) <- progPaths, prog==prog' ]))

programConfigurationOptions
  :: ProgramConfiguration
  -> ShowOrParseArgs
  -> (flags -> [(String, [String])])
  -> ([(String, [String])] -> (flags -> flags))
  -> [Option flags]
programConfigurationOptions progConf showOrParseArgs get set =
  case showOrParseArgs of
    -- we don't want a verbose help text list so we just show a generic one:
    ShowArgs  -> [programOptions  "PROG", programOption   "PROG"]
    ParseArgs -> map (programOptions . programName . fst) (knownPrograms progConf)
              ++ map (programOption  . programName . fst) (knownPrograms progConf)
  where
    programOptions prog =
      option "" [prog ++ "-options"]
        ("give extra options to " ++ prog)
        get set
        (reqArg "OPTS" (\args -> [(prog, splitArgs args)]) (const []))

    programOption prog =
      option "" [prog ++ "-option"]
        ("give an extra option to " ++ prog ++
         " (no need to quote options containing spaces)")
        get set
        (reqArg "OPT" (\arg -> [(prog, [arg])])
           (\progArgs -> concat [ args | (prog', args) <- progArgs, prog==prog' ]))
                

-- ------------------------------------------------------------
-- * GetOpt Utils
-- ------------------------------------------------------------

trueArg, falseArg :: (b -> Flag Bool) -> (Flag Bool -> b -> b) -> ArgDescr b
trueArg  = noArg (Flag True) (\f -> case f of Flag True  -> True; _ -> False)
falseArg = noArg (Flag False) (\f -> case f of Flag False -> True; _ -> False)

reqArgFlag :: String
           -> (b -> Flag String) -> (Flag String -> b -> b) -> ArgDescr b
reqArgFlag name = reqArg name Flag flagToList

optionVerbose :: (flags -> Flag Verbosity)
              -> (Flag Verbosity -> flags -> flags)
              -> Option flags
optionVerbose get set =
  option "v" ["verbose"]
    "Control verbosity (n is 0--3, default verbosity level is 1)"
    get set
    (optArg "n" (Flag . flagToVerbosity)
                (\f -> case f of
                         Flag v -> [Just (showForCabal v)]
                         _      -> []))

-- ------------------------------------------------------------
-- * Other Utils
-- ------------------------------------------------------------

-- | Arguments to pass to a @configure@ script, e.g. generated by
-- @autoconf@.
configureArgs :: Bool -> ConfigFlags -> [String]
configureArgs bcHack flags
  = hc_flag
 ++ optFlag  "with-hc-pkg" configHcPkg
 ++ optFlag' "prefix"      prefix
 ++ optFlag' "bindir"      bindir
 ++ optFlag' "libdir"      libdir
 ++ optFlag' "libexecdir"  libexecdir
 ++ optFlag' "datadir"     datadir
 ++ configConfigureArgs flags
  where
        hc_flag = case (configHcFlavor flags, configHcPath flags) of
                        (_, Flag hc_path) -> [hc_flag_name ++ hc_path]
                        (Flag hc, NoFlag) -> [hc_flag_name ++ showHC hc]
                        (NoFlag,NoFlag)   -> []
        hc_flag_name
            --TODO kill off thic bc hack when defaultUserHooks is removed.
            | bcHack    = "--with-hc="
	    | otherwise = "--with-compiler="
        optFlag name config_field = case config_field flags of
                        Flag p -> ["--" ++ name ++ "=" ++ p]
                        NoFlag -> []
        optFlag' name config_field = optFlag name (fmap fromPathTemplate
                                                 . config_field
                                                 . configInstallDirs)

        showHC GHC = "ghc"
        showHC NHC = "nhc98"
        showHC JHC = "jhc"
        showHC Hugs = "hugs"
        showHC c    = "unknown compiler: " ++ (show c)

-- | Helper function to split a string into a list of arguments.
-- It's supposed to handle quoted things sensibly, eg:
--
-- > splitArgs "--foo=\"C:\Program Files\Bar\" --baz"
-- >   = ["--foo=C:\Program Files\Bar", "--baz"]
--
splitArgs :: String -> [String]
splitArgs  = space []
  where
    space :: String -> String -> [String]
    space w []      = word w []
    space w ( c :s)
        | isSpace c = word w (space [] s)
    space w ('"':s) = string w s
    space w s       = nonstring w s

    string :: String -> String -> [String]
    string w []      = word w []
    string w ('"':s) = space w s
    string w ( c :s) = string (c:w) s

    nonstring :: String -> String -> [String]
    nonstring w  []      = word w []
    nonstring w  ('"':s) = string w s
    nonstring w  ( c :s) = space (c:w) s

    word [] s = s
    word w  s = reverse w : s

-- The test cases kinda have to be rewritten from the ground up... :/
--hunitTests :: [Test]
--hunitTests =
--    let m = [("ghc", GHC), ("nhc98", NHC), ("hugs", Hugs)]
--        (flags, commands', unkFlags, ers)
--               = getOpt Permute options ["configure", "foobar", "--prefix=/foo", "--ghc", "--nhc98", "--hugs", "--with-compiler=/comp", "--unknown1", "--unknown2", "--install-prefix=/foo", "--user", "--global"]
--       in  [TestLabel "very basic option parsing" $ TestList [
--                 "getOpt flags" ~: "failed" ~:
--                 [Prefix "/foo", GhcFlag, NhcFlag, HugsFlag,
--                  WithCompiler "/comp", InstPrefix "/foo", UserFlag, GlobalFlag]
--                 ~=? flags,
--                 "getOpt commands" ~: "failed" ~: ["configure", "foobar"] ~=? commands',
--                 "getOpt unknown opts" ~: "failed" ~:
--                      ["--unknown1", "--unknown2"] ~=? unkFlags,
--                 "getOpt errors" ~: "failed" ~: [] ~=? ers],
--
--               TestLabel "test location of various compilers" $ TestList
--               ["configure parsing for prefix and compiler flag" ~: "failed" ~:
--                    (Right (ConfigCmd (Just comp, Nothing, Just "/usr/local"), []))
--                   ~=? (parseArgs ["--prefix=/usr/local", "--"++name, "configure"])
--                   | (name, comp) <- m],
--
--               TestLabel "find the package tool" $ TestList
--               ["configure parsing for prefix comp flag, withcompiler" ~: "failed" ~:
--                    (Right (ConfigCmd (Just comp, Just "/foo/comp", Just "/usr/local"), []))
--                   ~=? (parseArgs ["--prefix=/usr/local", "--"++name,
--                                   "--with-compiler=/foo/comp", "configure"])
--                   | (name, comp) <- m],
--
--               TestLabel "simpler commands" $ TestList
--               [flag ~: "failed" ~: (Right (flagCmd, [])) ~=? (parseArgs [flag])
--                   | (flag, flagCmd) <- [("build", BuildCmd),
--                                         ("install", InstallCmd Nothing False),
--                                         ("sdist", SDistCmd),
--                                         ("register", RegisterCmd False)]
--                  ]
--               ]

{- Testing ideas:
   * IO to look for hugs and hugs-pkg (which hugs, etc)
   * quickCheck to test permutations of arguments
   * what other options can we over-ride with a command-line flag?
-}
