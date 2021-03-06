{-# LANGUAGE NoImplicitPrelude #-}
module Lamdu.Sugar.Convert.Expression.Actions
    ( addActions, makeAnnotation, makeActions
    ) where

import qualified Control.Lens as Lens
import qualified Data.Map as Map
import qualified Data.Store.Property as Property
import           Data.Store.Transaction (Transaction)
import           Data.UUID.Types (UUID)
import qualified Lamdu.Calc.Val as V
import qualified Lamdu.Data.Definition as Definition
import qualified Lamdu.Data.Ops as DataOps
import qualified Lamdu.Eval.Results.Process as ResultsProcess
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.Infer as Infer
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (ConvertM)
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import           Lamdu.Sugar.Convert.PostProcess (PostProcessResult(..), postProcessDef)
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types

import           Lamdu.Prelude

type T = Transaction

mkExtract ::
    Monad m => Input.Payload m a -> ConvertM m (T m ExtractDestination)
mkExtract exprPl =
    do
        ctx <- ConvertM.readContext
        case ctx ^. ConvertM.scScopeInfo . ConvertM.siMOuter of
            Nothing -> mkExtractToDef ctx exprPl <&> ExtractToDef
            Just outerScope ->
                mkExtractToLet (outerScope ^. ConvertM.osiPos) (exprPl ^. Input.stored)
                <&> ExtractToLet
            & return

mkExtractToDef ::
    Monad m => ConvertM.Context m -> Input.Payload m a -> T m EntityId
mkExtractToDef ctx exprPl =
    do
        newDefI <-
            Definition.Definition
            (Definition.BodyExpr (Definition.Expr valI deps)) scheme ()
            & DataOps.newPublicDefinitionWithPane cp
        GoodExpr <- postProcessDef newDefI
        let param = ExprIRef.globalId newDefI
        getVarI <- V.LVar param & V.BLeaf & ExprIRef.newValBody
        Property.set (exprPl ^. Input.stored) getVarI
        Infer.depsGlobalTypes . Lens.at param ?~ scheme
            & Property.pureModify (ctx ^. ConvertM.scFrozenDeps)
        -- Remove the extracted deps
        ctx ^. ConvertM.scPostProcessRoot & void
        EntityId.ofIRef newDefI & return
    where
        valI = exprPl ^. Input.stored . Property.pVal
        deps = ctx ^. ConvertM.scFrozenDeps . Property.pVal
        cp = ctx ^. ConvertM.scCodeAnchors
        scheme =
            Infer.makeScheme (ctx ^. ConvertM.scInferContext)
            (exprPl ^. Input.inferredType)

mkExtractToLet ::
    Monad m => ExprIRef.ValIProperty m -> ExprIRef.ValIProperty m -> T m EntityId
mkExtractToLet outerScope stored =
    do
        (newParam, lamI) <-
            if Property.value stored == extractPosI
            then
                -- Give entire binder body a name (replace binder body
                -- with "(\x -> x) stored")
                DataOps.newIdentityLambda
            else
                -- Give some subexpr in binder body a name (replace
                -- binder body with "(\x -> binderBody) stored", and
                -- stored becomes "x")
                do
                    newParam <- ExprIRef.newVar
                    lamI <-
                        V.Lam newParam extractPosI & V.BLam
                        & ExprIRef.newValBody
                    getVarI <- V.LVar newParam & V.BLeaf & ExprIRef.newValBody
                    Property.set stored getVarI
                    return (newParam, lamI)
        V.Apply lamI oldStored & V.BApp & ExprIRef.newValBody
            >>= Property.set outerScope
        EntityId.ofLambdaParam newParam & return
    where
        extractPosI = Property.value outerScope
        oldStored = Property.value stored

makeActions :: Monad m => Input.Payload m a -> ConvertM m (NodeActions (T m))
makeActions exprPl =
    do
        ext <- mkExtract exprPl
        postProcess <- ConvertM.postProcess
        pure NodeActions
            { _detach = DataOps.applyHoleTo stored <* postProcess <&> EntityId.ofValI & DetachAction
            , _mSetToHole = DataOps.setToHole stored <* postProcess <&> EntityId.ofValI & Just
            , _extract = ext
            , _mReplaceParent = Nothing
            }
    where
        stored = exprPl ^. Input.stored

addActions ::
    Monad m =>
    Input.Payload m a -> Body UUID (T m) (ExpressionU m a) ->
    ConvertM m (ExpressionU m a)
addActions exprPl body =
    do
        actions <- makeActions exprPl
        ann <- makeAnnotation exprPl
        protectedSetToVal <- ConvertM.typeProtectedSetToVal
        let setToExpr srcPl =
                plActions . mReplaceParent ?~
                (protectedSetToVal
                    (exprPl ^. Input.stored)
                    (srcPl ^. plData . pStored . Property.pVal)
                    <&> EntityId.ofValI)
        let addReplaceParent innerPl = setToExpr innerPl innerPl
        let fixFragmentReplaceParent child =
                -- Replace-parent with fragment sets directly to fragment expression
                case child ^. rBody of
                BodyFragment fragment ->
                    child
                    & rPayload %~ setToExpr (fragment ^. fExpr . rPayload)
                _ -> child
        let fixFragmentExprReplaceParent fragment =
                -- Replace-parent of fragment expr without "attach"
                -- available - replaces parent of fragment rather than
                -- fragment itself (i.e: replaces grandparent).
                case fragment ^. fAttach of
                AttachAction{} -> fragment
                AttachTypeMismatch ->
                    fragment
                    & fExpr . rPayload %~ setToExpr (fragment ^. fExpr . rPayload)
        return Expression
            { _rBody =
                body
                <&> rPayload %~ addReplaceParent
                <&> fixFragmentReplaceParent
                <&> rBody . _BodyFragment %~ fixFragmentExprReplaceParent
            , _rPayload =
                Payload
                { _plEntityId = exprPl ^. Input.entityId
                , _plAnnotation = ann
                , _plActions = actions
                , _plData =
                    ConvertPayload
                    { _pStored = exprPl ^. Input.stored
                    , _pUserData = exprPl ^. Input.userData
                    }
                }
            }

makeAnnotation :: Monad m => Input.Payload m a -> ConvertM m Annotation
makeAnnotation payload =
    do
        ctx <- ConvertM.readContext
        let mk res =
                do
                    Map.null res & not & guard
                    res <&> ResultsProcess.addTypes (ctx ^. ConvertM.scNominalsMap) typ & Just
        Annotation
            { _aInferredType = typ
            , _aMEvaluationResult =
                payload ^. Input.evalResults <&> (^. Input.eResults) <&> mk
            } & return
    where
        typ = payload ^. Input.inferredType
