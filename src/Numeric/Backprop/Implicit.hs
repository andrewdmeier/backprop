{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE PatternSynonyms     #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies        #-}
{-# LANGUAGE TypeOperators       #-}

module Numeric.Backprop.Implicit (
  -- * Types
    BPRef, BPOp, Op(..)
  , Summer(..), Unity(..)
  -- * Backpropagation
  , backprop, grad, eval
  , backprop', grad', eval'
  -- * Ref manipulation
  , BP.constRef, BP.liftR, BP.liftR1, BP.liftR2, BP.liftR3
  -- ** As Parts
  , partsRef, withParts
  , splitRefs, gSplit
  , partsRef', withParts'
  , splitRefs', gSplit'
  -- * Op
  , BP.op1, BP.op2, BP.op3, BP.opN
  , BP.op1', BP.op2', BP.op3', BP.opN'
  -- * Utility
  , summers, unities
  , Prod(..), pattern (:>), only, head'
  , Tuple, pattern (::<), only_
  ) where

import           Data.Type.Combinator
import           Data.Type.Index
import           Data.Type.Length
import           Data.Type.Product
import           Data.Type.Util
import           Lens.Micro hiding         (ix)
import           Lens.Micro.Extras
import           Numeric.Backprop.Internal
import           Numeric.Backprop.Iso
import           Numeric.Backprop.Op
import           Type.Class.Higher
import           Type.Class.Known
import qualified Generics.SOP              as SOP
import qualified Numeric.Backprop          as BP

type BPOp s rs a = Prod (BPRef s rs) rs -> BPRef s rs a

backprop'
    :: Prod Summer rs
    -> Prod Unity rs
    -> (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> (a, Tuple rs)
backprop' ss us f = BP.backprop' ss us $ BP.withInps' (prodLength ss) (return . f)

backprop
    :: (Known Length rs, Every Num rs)
    => (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> (a, Tuple rs)
backprop f = BP.backprop $ BP.withInps (return . f)

grad'
    :: Prod Summer rs
    -> Prod Unity rs
    -> (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> Tuple rs
grad' ss us f = snd . backprop' ss us f

grad
    :: (Known Length rs, Every Num rs)
    => (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> Tuple rs
grad f = snd . backprop f

eval'
    :: Prod Summer rs
    -> Prod Unity rs
    -> (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> a
eval' ss us f = fst . backprop' ss us f

eval
    :: (Known Length rs, Every Num rs)
    => (forall s. Prod (BPRef s rs) rs -> BPRef s rs a)
    -> Tuple rs
    -> a
eval f = fst . backprop f

partsRef'
    :: forall s rs bs a. ()
    => Prod Summer bs
    -> Prod Unity bs
    -> Iso' a (Tuple bs)
    -> BPRef s rs a
    -> Prod (BPRef s rs) bs
partsRef' ss us i r = imap1 (\ix u -> BP.liftR1 (BP.op1' (f ix u)) r) us
  where
    f :: Index bs b
      -> Unity b
      -> a
      -> (b, Maybe b -> a)
    f ix u x = ( getI . index ix . view i $ x
               , review i
               . flip (set (indexP ix)) zeroes
               . maybe (I (getUnity u)) I
               )
    zeroes :: Tuple bs
    zeroes = map1 (\s -> I $ runSummer s []) ss

partsRef
    :: forall s rs bs a. (Known Length bs, Every Num bs)
    => Iso' a (Tuple bs)
    -> BPRef s rs a
    -> Prod (BPRef s rs) bs
partsRef = partsRef' summers unities

withParts'
    :: forall s rs bs a r. ()
    => Prod Summer bs
    -> Prod Unity bs
    -> Iso' a (Tuple bs)
    -> BPRef s rs a
    -> (Prod (BPRef s rs) bs -> r)
    -> r
withParts' ss us i r f = f (partsRef' ss us i r)

withParts
    :: forall s rs bs a r. (Known Length bs, Every Num bs)
    => Iso' a (Tuple bs)
    -> BPRef s rs a
    -> (Prod (BPRef s rs) bs -> r)
    -> r
withParts i r f = f (partsRef i r)

splitRefs'
    :: forall s rs as. ()
    => Prod Summer as
    -> Prod Unity as
    -> BPRef s rs (Tuple as)
    -> Prod (BPRef s rs) as
splitRefs' ss us = partsRef' ss us id

splitRefs
    :: forall s rs as. (Known Length as, Every Num as)
    => BPRef s rs (Tuple as)
    -> Prod (BPRef s rs) as
splitRefs = partsRef id

gSplit'
    :: forall s rs as a. (SOP.Generic a, SOP.Code a ~ '[as])
    => Prod Summer as
    -> Prod Unity as
    -> BPRef s rs a
    -> Prod (BPRef s rs) as
gSplit' ss us = partsRef' ss us gTuple

gSplit
    :: forall s rs as a. (SOP.Generic a, SOP.Code a ~ '[as], Known Length as, Every Num as)
    => BPRef s rs a
    -> Prod (BPRef s rs) as
gSplit = partsRef gTuple

-- TODO: figure out how to split sums
