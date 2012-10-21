-- Module for connecting to the AUR servers,
-- downloading PKGBUILDs and source tarballs, and handling them.

{-

Copyright 2012 Colin Woodbury <colingw@gmail.com>

This file is part of Aura.

Aura is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Aura is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Aura.  If not, see <http://www.gnu.org/licenses/>.

-}

module Aura.AurConnection where

-- System Libaries
import System.FilePath ((</>))
import Data.Maybe (fromJust)
import Text.JSON

-- Custom Libraries
import Internet
import Bash

-----------------------
-- AUR API URL CREATION
-----------------------
data RPCType = PkgSearch | MultiInfo | MSearch deriving (Eq)

makeRPCUrl :: RPCType -> [String] -> String
makeRPCUrl t args = rpcBaseUrl ++ t' ++ args'
    where t'    = rpcAddType t
          args' = if t == MultiInfo
                  then rpcAddMultiInfoArgs args
                  else rpcAddArg args

aurPkgUrl :: String -> String
aurPkgUrl n = "https://aur.archlinux.org/packages.php?ID=" ++ n

rpcBaseUrl :: String
rpcBaseUrl = "https://aur.archlinux.org/rpc.php?"

rpcAddType :: RPCType -> String
rpcAddType t = "type=" ++ case t of
                            PkgSearch -> "search"
                            MultiInfo -> "multiinfo"
                            MSearch   -> "msearch"

rpcAddArg :: [String] -> String
rpcAddArg []    = []
rpcAddArg (a:_) = "&arg=" ++ a  -- This needs to be fixed! Regex!

rpcAddMultiInfoArgs :: [String] -> String
rpcAddMultiInfoArgs = concat . map ("&arg[]=" ++)

-------
-- JSON
-------
-- Extend this later as needed.
data PkgInfo = PkgInfo { nameOf :: String
                       , latestVerOf :: String
                       , isOutOfDate :: Bool
                       , projectURLOf :: String
                       , aurURLOf :: String
                       , licenseOf :: String
                       , votesOf :: String
                       , descriptionOf :: String
                       } deriving (Eq,Show)

aurSearchLookup :: String -> IO (Either String [PkgInfo])
aurSearchLookup regex = getAURPkgInfo [regex] PkgSearch

aurInfoLookup :: [String] -> IO (Either String [PkgInfo])
aurInfoLookup pkgs = getAURPkgInfo pkgs MultiInfo

getAURPkgInfo :: [String] -> RPCType -> IO (Either String [PkgInfo])
getAURPkgInfo items rpcType = do
  infoJSON <- getUrlContents $ makeRPCUrl rpcType items
  return . resultToEither . parseInfoJSON $ infoJSON

-- Monads rock my world.
parseInfoJSON :: String -> Result [PkgInfo]
parseInfoJSON json = decode json >>= apiFailCheck >>= forgePkgInfo
    where forgePkgInfo j = valFromObj "results" j >>= mapM makePkgInfo

apiFailCheck :: JSObject JSValue -> Result (JSObject JSValue)
apiFailCheck json = do
  isError <- valFromObj "type" json >>= return . (== "error")
  if isError then Error "AUR API lookup failed." else Ok json

makePkgInfo :: JSObject JSValue -> Result PkgInfo
makePkgInfo pkgJSON = do
  ur <- valFromObj "URL" pkgJSON
  na <- valFromObj "Name" pkgJSON
  ve <- valFromObj "Version" pkgJSON
  li <- valFromObj "License" pkgJSON
  vo <- valFromObj "NumVotes" pkgJSON
  de <- valFromObj "Description" pkgJSON
  au <- valFromObj "ID" pkgJSON >>= return . aurPkgUrl
  ou <- valFromObj "OutOfDate" pkgJSON >>= return . (/= "0")
  return $ PkgInfo na ve ou ur au li vo de
{-
makePkgInfo pkgJSON = makePkgInfo' (\x -> PkgInfo x) pkgJSON fields
    where fields = [ "Name","Version","URL","License"
                   , "NumVotes","OutOfDate","Description" ]

makePkgInfo' acc pkgJSON []     = return acc
makePkgInfo' acc pkgJSON (f:fs) = do
  x <- valFromObj f pkgJSON
  makePkgInfo' (acc x) pkgJSON fs
-}
{- Is this possible?
  return $ foldl PkgInfo `liftM` mapM (flip valFromObj pkgJSON) fields
  where fields = [ "Name","Version","URL","License"
                 , "NumVotes","OutOfDate","Description" ]
-}

------------
-- PKGBUILDS
------------
type Pkgbuild = String

aurLink :: String
aurLink = "https://aur.archlinux.org/packages/"

getPkgBaseUrl :: String -> String
getPkgBaseUrl pkg = aurLink </> take 2 pkg </> pkg

getPkgbuildUrl :: String -> String
getPkgbuildUrl pkg = getPkgBaseUrl pkg </> "PKGBUILD"                     

-- Assumption: The package given EXISTS as an AUR package.
downloadPkgbuild :: String -> IO Pkgbuild
downloadPkgbuild = getUrlContents . getPkgbuildUrl

getTrueVerViaPkgbuild :: Pkgbuild -> String
getTrueVerViaPkgbuild pkgb = pkgver ++ "-" ++ pkgrel
    where globals = getGlobalVars pkgb
          pkgver  = fromJust $ referenceValue globals "pkgver"
          pkgrel  = fromJust $ referenceValue globals "pkgrel"

--getPkgbuildField :: String -> Pkgbuild -> [String]
--getPkgbuildField = getField

------------------
-- SOURCE TARBALLS
------------------
getTarballUrl :: String -> String
getTarballUrl pkg = getPkgBaseUrl pkg </> pkg ++ ".tar.gz"

downloadSource :: FilePath -> String -> IO FilePath
downloadSource path = saveUrlContents path . getTarballUrl 
