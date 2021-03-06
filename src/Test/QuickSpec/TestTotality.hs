-- | Test whether functions are total.
--   Used by HipSpec.

{-# LANGUAGE CPP, TupleSections #-}
module Test.QuickSpec.TestTotality where

#include "errors.h"
import Prelude hiding (lookup)
import Test.QuickSpec.Reasoning.PartialEquationalReasoning hiding (Variable, total, partial)
import qualified Test.QuickSpec.Reasoning.PartialEquationalReasoning as PEQ
import Test.QuickSpec.Utils.TypeRel
import qualified Test.QuickSpec.Utils.TypeMap as TypeMap
import Test.QuickSpec.Utils.Typed
import Test.QuickSpec.Utils.Typeable
import Test.QuickSpec.Utils
import Test.QuickSpec.Signature
import Test.QuickSpec.Term hiding (symbols)
import Test.QuickCheck
import Test.QuickCheck.Gen
import System.Random
import Control.Monad
import Data.List hiding (lookup)
import Data.Maybe
import Data.Ord
import qualified Data.Map as Map

testTotality :: Sig -> IO [(Symbol, Totality)]
testTotality sig = do
  consts <- mapM (some constTotality) (toList (constants sig))
  let vars = map (some varTotality) (toList (variables sig))
  return (sortBy (comparing fst) (consts ++ vars))
  where
    constTotality :: Typeable a => Constant a -> IO (Symbol, Totality)
    constTotality (Constant x) = fmap (sym x,) (isTotal (symbolArity (sym x)) (value x))

    isTotal :: Typeable a => Int -> a -> IO Totality
    isTotal arity x = do
      b <- always sig (testTotal x [])
      if not b then return Partial
        else fmap Total . flip filterM [0..arity-1] $ \i -> always sig (testTotal x [i])

    testTotal :: Typeable a => a -> [Int] -> Gen Bool
    testTotal f args =
      case witnessArrow sig f of
        Nothing ->
          case observe undefined sig of
            Observer obs ->
              fmap (isJust . spoony) (liftM2 ($) (totalGen obs) (return f))
        Just (Some (Witness arg), Some (Witness res)) -> do
          if 0 `elem` args && typeOf res `Map.notMember` partial sig
            then return False
            else do
              x <- TypeMap.lookup __ arg
                   (if 0 `elem` args then partial sig else total sig)
              case cast f `asTypeOf` Just (\x -> (x `asTypeOf` arg) `seq` (undefined `asTypeOf` res)) of
                Just g -> testTotal (g x) (map pred args)

    varTotality :: Variable a -> (Symbol, Totality)
    varTotality (Variable x) = (sym x, PEQ.Variable)

testEquation :: Typeable a => Sig -> Expr a -> Expr a -> Symbol -> IO Bool
testEquation sig e1 e2 s =
  case observe undefined sig of
    Observer obs ->
      always sig $ do
        let strat s' = if s == s' then partialGen else totalGen
        obs' <- partialGen obs
        v <- valuation strat
        return (spoony (obs' (eval e1 v)) == spoony (obs' (eval e2 v)))

always :: Sig -> Gen Bool -> IO Bool
always sig x = do
  gens <- replicateM 100 newStdGen
  let sizes = cycle [0,2..maxQuickCheckSize sig]
  return (and [unGen x g n | (g, n) <- zip gens sizes])
