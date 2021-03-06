{-# LANGUAGE NoImplicitPrelude, OverloadedStrings, RankNTypes, NoMonomorphismRestriction #-}
module Lamdu.GUI.ExpressionEdit.NomEdit
    ( makeFromNom, makeToNom
    ) where

import qualified Control.Lens as Lens
import qualified Control.Monad.Reader as Reader
import           Data.Store.Transaction (Transaction)
import qualified GUI.Momentu.Align as Align
import qualified GUI.Momentu.EventMap as E
import           GUI.Momentu.Glue ((/|/))
import qualified GUI.Momentu.Responsive as Responsive
import qualified GUI.Momentu.Responsive.Expression as ResponsiveExpr
import qualified GUI.Momentu.Widget as Widget
import qualified GUI.Momentu.Widgets.TextView as TextView
import qualified Lamdu.Config as Config
import qualified Lamdu.Config.Theme as Theme
import qualified Lamdu.GUI.ExpressionEdit.BinderEdit as BinderEdit
import           Lamdu.GUI.ExpressionGui.Wrap (stdWrapParentExpr)
import           Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import           Lamdu.GUI.ExpressionGui (ExpressionGui)
import qualified Lamdu.GUI.ExpressionGui as ExprGui
import qualified Lamdu.GUI.NameEdit as NameEdit
import qualified Lamdu.GUI.Styled as Styled
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.Name (Name(..))
import qualified Lamdu.Name as Name
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

type T = Transaction

mReplaceParent :: Lens.Traversal' (Sugar.Expression name (T m) a) (T m Sugar.EntityId)
mReplaceParent = Sugar.rPayload . Sugar.plActions . Sugar.mReplaceParent . Lens._Just

makeToNom ::
    forall m.
    Monad m =>
    Sugar.Nominal (Name (T m)) (Sugar.BinderBody (Name (T m)) (T m) (ExprGui.SugarExpr m)) ->
    Sugar.Payload (T m) ExprGui.Payload ->
    ExprGuiM m (ExpressionGui m)
makeToNom nom pl =
    nom <&> BinderEdit.makeBinderBodyEdit
    & mkNomGui id "ToNominal" "«" mDel pl
    where
        bbContent = nom ^. Sugar.nVal . Sugar.bbContent
        mDel = bbContent ^? Sugar._BinderExpr . mReplaceParent

makeFromNom ::
    Monad m =>
    Sugar.Nominal (Name (T m)) (ExprGui.SugarExpr m) ->
    Sugar.Payload (T m) ExprGui.Payload ->
    ExprGuiM m (ExpressionGui m)
makeFromNom nom pl =
    nom <&> ExprGuiM.makeSubexpression
    & mkNomGui reverse "FromNominal" "»" mDel pl
    where
        mDel = nom ^? Sugar.nVal . mReplaceParent

mkNomGui ::
    Monad m =>
    (forall a. [a] -> [a]) ->
    Text -> Text -> Maybe (T m Sugar.EntityId) ->
    Sugar.Payload (T m) ExprGui.Payload ->
    Sugar.Nominal (Name (T m)) (ExprGuiM m (ExpressionGui m)) ->
    ExprGuiM m (ExpressionGui m)
mkNomGui ordering nomStr str mDel pl (Sugar.Nominal tid val) =
    do
        nomColor <- Lens.view Theme.theme <&> Theme.codeForegroundColors <&> Theme.nomColor
        config <- Lens.view Config.config
        let mkEventMap action =
                action <&> WidgetIds.fromEntityId
                & E.keysEventMapMovesCursor (Config.delKeys config)
                (E.Doc ["Edit", "Nominal", "Delete " <> nomStr])
        let eventMap = mDel ^. Lens._Just . Lens.to mkEventMap
        stdWrapParentExpr pl
            <*> ( (ResponsiveExpr.boxSpacedMDisamb ?? mParenInfo)
                    <*>
                    ( ordering
                        [
                        do
                            label <- Styled.grammarLabel str
                            nameGui <-
                                NameEdit.makeView
                                (tid ^. Sugar.tidName . Name.form)
                            Widget.makeFocusableView ?? nameId
                                <&> (Align.tValue %~) ?? label /|/ nameGui
                        <&> Responsive.fromWithTextPos
                        & Reader.local (TextView.color .~ nomColor)
                        <&> Widget.weakerEvents eventMap
                    , val
                    ] & sequence
                    )
                )
    where
        mParenInfo
            | pl ^. Sugar.plData . ExprGui.plNeedParens =
                Widget.toAnimId myId & Just
            | otherwise = Nothing
        myId = WidgetIds.fromExprPayload pl
        nameId = Widget.joinId myId ["name"]
