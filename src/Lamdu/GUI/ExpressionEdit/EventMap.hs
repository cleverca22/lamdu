{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}
module Lamdu.GUI.ExpressionEdit.EventMap
    ( add
    , Options(..), defaultOptions
    , ExprInfo(..), addWith
    , jumpHolesEventMap
    , extractCursor
    , wrapEventMap
    ) where

import qualified Control.Lens as Lens
import qualified Data.Store.Transaction as Transaction
import qualified Data.Text as Text
import           GUI.Momentu.EventMap (EventMap)
import qualified GUI.Momentu.EventMap as E
import qualified GUI.Momentu.State as GuiState
import           GUI.Momentu.Widget (HasWidget(..), EventContext)
import qualified GUI.Momentu.Widget as Widget
import qualified Lamdu.CharClassification as Chars
import qualified Lamdu.Config as Config
import qualified Lamdu.GUI.ExpressionEdit.HoleEdit.State as HoleEditState
import qualified Lamdu.GUI.ExpressionEdit.HoleEdit.WidgetIds as HoleWidgetIds
import qualified Lamdu.GUI.ExpressionGui as ExprGui
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import           Lamdu.Precedence (Prec, precedence)
import           Lamdu.Sugar.NearestHoles (NearestHoles)
import qualified Lamdu.Sugar.NearestHoles as NearestHoles
import           Lamdu.Sugar.Parens (MinOpPrec)
import qualified Lamdu.Sugar.Types as Sugar

import           Lamdu.Prelude

type T = Transaction.Transaction

data ExprInfo m = ExprInfo
    { exprInfoIsHoleResult :: Bool
    , exprInfoNearestHoles :: NearestHoles
    , exprInfoActions :: Sugar.Actions (T m)
    , exprInfoMinOpPrec :: MinOpPrec
    }

newtype Options = Options
    { addOperatorSetHoleState :: Maybe Sugar.EntityId
    }

defaultOptions :: Options
defaultOptions =
    Options
    { addOperatorSetHoleState = Nothing
    }

exprInfoFromPl :: Sugar.Payload (T f) ExprGui.Payload -> ExprInfo f
exprInfoFromPl pl =
    ExprInfo
    { exprInfoIsHoleResult = ExprGui.isHoleResult pl
    , exprInfoNearestHoles = pl ^. Sugar.plData . ExprGui.plNearestHoles
    , exprInfoActions = pl ^. Sugar.plActions
    , exprInfoMinOpPrec = pl ^. Sugar.plData . ExprGui.plMinOpPrec
    }

add ::
    (MonadReader env m, Monad f, Config.HasConfig env, HasWidget w) =>
    Options -> Sugar.Payload (T f) ExprGui.Payload ->
    m (w (T f GuiState.Update) -> w (T f GuiState.Update))
add options = addWith options . exprInfoFromPl

addWith ::
    (MonadReader env m, Monad f, Config.HasConfig env, HasWidget w) =>
    Options -> ExprInfo f -> m (w (T f GuiState.Update) -> w (T f GuiState.Update))
addWith options exprInfo =
    do
        actions <- actionsEventMap options exprInfo
        nav <- jumpHolesEventMap (exprInfoNearestHoles exprInfo)
        (widget . Widget.eventMapMaker . Lens.mapped <>~ nav)
            . Widget.weakerEventsWithContext actions
            & pure

jumpHolesEventMap ::
    (MonadReader env m, Config.HasConfig env, Monad f) =>
    NearestHoles -> m (EventMap (T f GuiState.Update))
jumpHolesEventMap hg =
    Lens.view Config.config <&> Config.hole
    <&>
    \config ->
    let jumpEventMap keys dirStr lens =
            case hg ^. lens of
            Nothing -> mempty
            Just dest ->
                WidgetIds.fromEntityId dest & pure
                & E.keysEventMapMovesCursor (keys config)
                    (E.Doc ["Navigation", "Jump to " <> dirStr <> " hole"])
    in
    jumpEventMap Config.holeJumpToNextKeys "next" NearestHoles.next
    <>
    jumpEventMap Config.holeJumpToPrevKeys "previous" NearestHoles.prev

extractCursor :: Sugar.ExtractDestination -> Widget.Id
extractCursor (Sugar.ExtractToLet letId) =
    WidgetIds.fromEntityId letId & WidgetIds.letBinderId
extractCursor (Sugar.ExtractToDef defId) =
    WidgetIds.nameEditOf (WidgetIds.fromEntityId defId)

extractEventMap ::
    (MonadReader env m, Config.HasConfig env, Functor f) =>
    Sugar.Actions (T f) -> m (EventMap (T f GuiState.Update))
extractEventMap actions =
    Lens.view Config.config <&> Config.extractKeys
    <&>
    \k ->
    actions ^. Sugar.extract <&> extractCursor
    & E.keysEventMapMovesCursor k doc
    where
        doc = E.Doc ["Edit", "Extract"]

actionsEventMap ::
    (MonadReader env m, Monad f, Config.HasConfig env) =>
    Options -> ExprInfo f ->
    m (EventContext -> EventMap (T f GuiState.Update))
actionsEventMap options exprInfo =
    sequence
    [ case exprInfoActions exprInfo ^. Sugar.wrap of
      Sugar.WrapAction act -> wrapEventMap act
      _ -> return mempty
    , if exprInfoIsHoleResult exprInfo
        then return mempty
        else
            sequence
            [ extractEventMap (exprInfoActions exprInfo)
            , Lens.view Config.config <&> Config.replaceParentKeys <&> mkReplaceParent
            ] <&> mconcat
    , replaceEventMap (exprInfoActions exprInfo)
    ] <&> mconcat <&> const
    <&> mappend (applyOperatorEventMap options exprInfo)
    where
        mkReplaceParent replaceKeys =
            exprInfoActions exprInfo ^. Sugar.mReplaceParent <&> void
            & maybe mempty (E.keysEventMap replaceKeys (E.Doc ["Edit", "Replace parent"]))

-- | Create the hole search term for new apply operators,
-- given the extra search term chars from another hole.
applyOperatorSearchTerm :: Prec -> EventContext -> EventMap Text
applyOperatorSearchTerm minOpPrec eventCtx =
    E.charGroup Nothing (E.Doc ["Edit", "Apply operator"])
    ops (Text.singleton <&> (searchStrRemainder <>))
    where
        searchStrRemainder = eventCtx ^. Widget.ePrevTextRemainder
        ops =
            case Text.uncons searchStrRemainder of
            Nothing -> filter acceptOp Chars.operator
            Just (firstOp, _)
                | acceptOp firstOp -> Chars.operator
                | otherwise -> mempty
        acceptOp = (>= minOpPrec) . precedence

applyOperatorEventMap ::
    Monad f => Options -> ExprInfo f -> EventContext -> EventMap (T f GuiState.Update)
applyOperatorEventMap options exprInfo eventCtx =
    case exprInfoActions exprInfo ^. Sugar.wrap of
    Sugar.WrapAction wrap ->
        case addOperatorSetHoleState options of
        Just holeId -> pure holeId
        Nothing -> wrap
    Sugar.WrapperAlready holeId -> return holeId
    Sugar.WrappedAlready holeId -> return holeId
    & action
    where
        action wrap =
            applyOperatorSearchTerm (exprInfoMinOpPrec exprInfo) eventCtx
            <&> HoleEditState.setHoleStateAndJump
            <&> (wrap <&>)

wrapEventMap ::
    (MonadReader env m, Config.HasConfig env, Monad f) =>
    T f Sugar.EntityId -> m (EventMap (T f GuiState.Update))
wrapEventMap wrap =
    Lens.view Config.config
    <&>
    \config ->
    E.keysEventMapMovesCursor (Config.wrapKeys config)
    (E.Doc ["Edit", "Modify"])
    (wrap <&> HoleWidgetIds.make <&> HoleWidgetIds.hidOpen)
    <>
    E.keysEventMap (Config.parenWrapKeys config)
    (E.Doc ["Edit", "Wrap with hole"])
    (void wrap)

replaceEventMap ::
    (MonadReader env m, Config.HasConfig env, Monad f) =>
    Sugar.Actions (T f) -> m (EventMap (T f GuiState.Update))
replaceEventMap actions =
    Lens.view Config.config
    <&>
    \config ->
    let mk action =
            action <&> WidgetIds.fromEntityId
            & E.keysEventMapMovesCursor (Config.delKeys config) (E.Doc ["Edit", "Delete expression"])
    in
    case actions ^. Sugar.delete of
    Sugar.SetToHole action -> mk (action <&> snd)
    Sugar.Delete action -> mk action
    Sugar.CannotDelete -> mempty
