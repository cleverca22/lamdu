{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, DeriveTraversable #-}

module Lamdu.Sugar.Convert.Binder.Redex
    ( Redex(..)
      , lam
      , paramRefs
      , arg
      , hiddenPayloads
    , check
    ) where

import qualified Control.Lens as Lens
import qualified Lamdu.Calc.Val as V
import           Lamdu.Calc.Val.Annotated (Val(..))
import qualified Lamdu.Calc.Val.Annotated as Val
import qualified Lamdu.Expr.Lens as ExprLens
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Types

import           Lamdu.Prelude

data Redex a = Redex
    { _lam :: V.Lam (Val a)
    , _paramRefs :: [EntityId]
    , _arg :: Val a
    , _hiddenPayloads :: [a]
    } deriving (Functor, Foldable, Traversable)
Lens.makeLenses ''Redex

check :: Val (Input.Payload m a) -> Maybe (Redex (Input.Payload m a))
check expr = do
    V.Apply func a <- expr ^? ExprLens.valApply
    l <- func ^? Val.body . V._BLam
    Just Redex
        { _lam = l
        , _arg = a
        , _hiddenPayloads = (^. Val.payload) <$> [expr, func]
        , _paramRefs = func ^. Val.payload . Input.varRefsOfLambda
        }
