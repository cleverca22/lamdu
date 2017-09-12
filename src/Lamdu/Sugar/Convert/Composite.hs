{-# LANGUAGE NoImplicitPrelude #-}

module Lamdu.Sugar.Convert.Composite
    ( convertCompositeItem, setTagOrder, makeAddItem
    ) where

import qualified Data.Set as Set
import           Data.Store.Property (Property)
import qualified Data.Store.Property as Property
import           Data.Store.Transaction (Transaction)
import qualified Data.Store.Transaction as Transaction
import           Data.UUID.Types (UUID)
import qualified Lamdu.Calc.Type as T
import           Lamdu.Calc.Val.Annotated (Val(..))
import qualified Lamdu.Data.Anchors as Anchors
import qualified Lamdu.Data.Ops as DataOps
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.Expr.UniqueId as UniqueId
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (ConvertM)
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types

import           Lamdu.Prelude

type T = Transaction

deleteItem ::
    Monad m =>
    ExprIRef.ValIProperty m -> ExprIRef.ValI m ->
    ConvertM m (T m EntityId)
deleteItem stored restI =
    do
        protectedSetToVal <- ConvertM.typeProtectedSetToVal
        protectedSetToVal stored restI <&> EntityId.ofValI & return

convertCompositeItem ::
    (Monad m, Monoid a) =>
    ExprIRef.ValIProperty m ->
    ExprIRef.ValI m ->
    EntityId -> Property (T m) T.Tag -> Val (Input.Payload m a) ->
    ConvertM m (CompositeItem UUID m (ExpressionU m a))
convertCompositeItem stored restI inst tagProperty expr =
    do
        exprS <- ConvertM.convertSubexpression expr
        delItem <- deleteItem stored restI
        sugarContext <- ConvertM.readContext
        return CompositeItem
            { _ciTag =
                Tag
                { _tagInfo = TagInfo inst tag
                , _tagName = UniqueId.toUUID tag
                , _tagActions =
                    TagActions
                    { _taChangeTag = tagProperty ^. Property.pSet
                    , _taOptions =
                        sugarContext ^. ConvertM.scCodeAnchors
                        & Anchors.tags & Transaction.getP
                        <&> Set.toList
                        <&> map toOption
                    }
                }
            , _ciExpr = exprS
            , _ciDelete = delItem
            }
    where
        toOption x = (UniqueId.toUUID x, x)
        tag = tagProperty ^. Property.pVal

setTagOrder :: Monad m => Int -> CompositeAddItemResult -> T m CompositeAddItemResult
setTagOrder i r =
    do
        Transaction.setP (Anchors.assocTagOrder (r ^. cairNewTag . tagVal)) i
        return r

makeAddItem :: Monad m =>
    (ExprIRef.ValI m -> T m (DataOps.CompositeExtendResult m)) ->
    ExprIRef.ValIProperty m ->
    ConvertM m (T m CompositeAddItemResult)
makeAddItem addItem stored =
    do
        protectedSetToVal <- ConvertM.typeProtectedSetToVal
        do
            DataOps.CompositeExtendResult tag newValI resultI <- addItem (stored ^. Property.pVal)
            _ <- protectedSetToVal stored resultI
            let resultEntity = EntityId.ofValI resultI
            return
                CompositeAddItemResult
                { _cairNewTag = TagInfo (EntityId.ofRecExtendTag resultEntity) tag
                , _cairNewVal = EntityId.ofValI newValI
                , _cairItem = resultEntity
                }
            & return
