{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.InjectEdit
    ( make
    ) where

import qualified Control.Lens as Lens
import           Control.Monad.Transaction (MonadTransaction)
import           Data.Store.Transaction (Transaction)
import           GUI.Momentu.Align (WithTextPos)
import qualified GUI.Momentu.Element as Element
import qualified GUI.Momentu.EventMap as E
import           GUI.Momentu.Glue ((/|/))
import qualified GUI.Momentu.Hover as Hover
import qualified GUI.Momentu.Responsive as Responsive
import qualified GUI.Momentu.Responsive.Expression as ResponsiveExpr
import qualified GUI.Momentu.Responsive.Options as Options
import           GUI.Momentu.View (View)
import qualified GUI.Momentu.Widget as Widget
import qualified GUI.Momentu.Widgets.Menu as Menu
import qualified GUI.Momentu.Widgets.Spacer as Spacer
import qualified GUI.Momentu.Widgets.TextEdit as TextEdit
import qualified GUI.Momentu.Widgets.TextView as TextView
import           Lamdu.Config (HasConfig)
import qualified Lamdu.Config as Config
import           Lamdu.Config.Theme (HasTheme)
import qualified Lamdu.GUI.ExpressionEdit.TagEdit as TagEdit
import           Lamdu.GUI.ExpressionGui (ExpressionGui)
import qualified Lamdu.GUI.ExpressionGui as ExpressionGui
import           Lamdu.GUI.ExpressionGui.Monad (ExprGuiM)
import qualified Lamdu.GUI.ExpressionGui.Monad as ExprGuiM
import qualified Lamdu.GUI.ExpressionGui.Types as ExprGuiT
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.Name (Name(..))
import           Lamdu.Sugar.NearestHoles (NearestHoles)
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

type T = Transaction

makeCommon ::
    ( Monad m, MonadReader env f, MonadTransaction m f
    , HasConfig env, HasTheme env, Widget.HasCursor env, TextEdit.HasStyle env
    , Spacer.HasStdSpacing env, Element.HasAnimIdPrefix env, Menu.HasStyle env
    , Hover.HasStyle env
    ) =>
    Options.Disambiguators (T m Widget.EventResult) ->
    Sugar.Tag (Name (T m)) (T m) ->
    Maybe (T m Sugar.EntityId) ->
    NearestHoles -> WithTextPos View -> [ExpressionGui m] ->
    f (ExpressionGui m)
makeCommon disamb tag mDelInject nearestHoles colonLabel valEdits =
    do
        config <- Lens.view Config.config
        let delEventMap =
                case mDelInject of
                Nothing -> mempty
                Just del ->
                    del <&> WidgetIds.fromEntityId
                    & Widget.keysEventMapMovesCursor (Config.delKeys config) (E.Doc ["Edit", "Delete"])
        (Options.boxSpaced ?? disamb)
            <*>
            ( TagEdit.makeCaseTag TagEdit.WithoutTagHoles nearestHoles tag
                <&> (/|/ colonLabel)
                <&> Lens.mapped %~ E.weakerEvents delEventMap
                <&> Responsive.fromWithTextPos <&> (: valEdits)
            )

injectIndicator ::
    ( MonadReader env f, TextView.HasStyle env, HasTheme env
    , Element.HasAnimIdPrefix env
    ) => Text -> f (WithTextPos View)
injectIndicator text =
    (ExpressionGui.grammarText ?? text) <*> Element.subAnimId ["injectIndicator"]

make ::
    Monad m =>
    Sugar.Inject (Name (T m)) (T m) (ExprGuiT.SugarExpr m) ->
    Sugar.Payload (T m) ExprGuiT.Payload ->
    ExprGuiM m (ExpressionGui m)
make (Sugar.Inject tag mVal) pl =
    case mVal of
    Nothing ->
        do
            dot <- injectIndicator "."
            makeCommon
                -- Give the tag widget the identity of the whole inject
                Options.disambiguationNone
                (tag & Sugar.tagInfo . Sugar.tagInstance .~ (pl ^. Sugar.plEntityId))
                Nothing (pl ^. Sugar.plData . ExprGuiT.plNearestHoles) dot []
        & ExpressionGui.stdWrap "InjectEdit" pl
    Just val ->
        do
            disamb <-
                case mParensId of
                Nothing -> pure Options.disambiguationNone
                Just parensId -> ResponsiveExpr.disambiguators ?? parensId
            arg <-
                ExprGuiM.makeSubexpression val <&> (:[])
            colon <- injectIndicator ":"
            makeCommon disamb tag replaceParent (ExprGuiT.nextHolesBefore val) colon arg
        & ExpressionGui.stdWrapParentExpr "InjectEdit" pl tagInstance
        where
            mParensId
                | pl ^. Sugar.plData . ExprGuiT.plNeedParens =
                  Just animId
                | otherwise = Nothing
            tagInstance = tag ^. Sugar.tagInfo . Sugar.tagInstance
            replaceParent = val ^. Sugar.rPayload . Sugar.plActions . Sugar.mReplaceParent
            animId = WidgetIds.fromExprPayload pl & Widget.toAnimId
