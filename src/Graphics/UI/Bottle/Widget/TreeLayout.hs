-- | TreeLayout is a layout form intended for visualizing tree-data,
-- such as program code.
--
-- Its design goals are:
--
-- * Make good use of the available screen real-estate.
-- * Avoid horizontal scroll
-- * Display the hierarchy/tree structure clearly
-- * Make the layout changes due to edits predictable and easy to follow
--
-- Subtrees are laid out horizontally as long as they fit within the
-- available horizontal space, to avoid horizontal scrolling.
--
-- When there is not enough horizontal space to lay the entire tree
-- horizontally, vertical layouts are used for the upper parts of the tree.
--
-- Hierarchy disambiguation happens using parentheses and indentation,
-- but only when necessary. For example: a horizontally laid out child
-- of a vertically laid out parent will not use parentheses as the
-- hierarchy is already clear in the layout itself.

{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, DeriveFunctor, FlexibleContexts, FlexibleInstances, MultiParamTypeClasses, TypeFamilies, UndecidableInstances #-}

module Graphics.UI.Bottle.Widget.TreeLayout
    ( TreeLayout(..), render

    -- * Layout params
    , LayoutParams(..), layoutMode, layoutContext
    , LayoutMode(..), _LayoutNarrow, _LayoutWide
    , LayoutDisambiguationContext(..)

    -- * Lenses
    , alignedWidget, alignment, modeWidths

    -- * Leaf generation
    , fromAlignedWidget, fromWidget, fromView, empty

    -- * Combinators
    , vbox, vboxSpaced, taggedList
    ) where

import qualified Control.Lens as Lens
import qualified Data.List as List
import           Data.Vector.Vector2 (Vector2(..))
import qualified Graphics.UI.Bottle.EventMap as E
import           Graphics.UI.Bottle.View (View, (/|/))
import qualified Graphics.UI.Bottle.View as View
import           Graphics.UI.Bottle.Widget (Widget, R)
import qualified Graphics.UI.Bottle.Widget as Widget
import           Graphics.UI.Bottle.Align (Aligned(..), AlignTo(..))
import qualified Graphics.UI.Bottle.Align as Align
import qualified Graphics.UI.Bottle.Widgets.Spacer as Spacer

import           Lamdu.Prelude

data LayoutMode
    = LayoutNarrow Widget.R -- ^ limited by the contained width field
    | LayoutWide -- ^ no limit on width
Lens.makePrisms ''LayoutMode

modeWidths :: Lens.Traversal' LayoutMode Widget.R
modeWidths _ LayoutWide = pure LayoutWide
modeWidths f (LayoutNarrow limit) = f limit <&> LayoutNarrow

-- The relevant context for knowing whether parenthesis/indentation is needed
data LayoutDisambiguationContext
    = LayoutClear
    | LayoutHorizontal
    | LayoutVertical

data LayoutParams = LayoutParams
    { _layoutMode :: LayoutMode
    , _layoutContext :: LayoutDisambiguationContext
    }
Lens.makeLenses ''LayoutParams

newtype TreeLayout a = TreeLayout
    { _render :: LayoutParams -> Aligned (Widget a)
    } deriving Functor
Lens.makeLenses ''TreeLayout

adjustWidth ::
    View.HasSize v => View.Orientation -> v -> TreeLayout a -> TreeLayout a
adjustWidth View.Vertical _ = id
adjustWidth View.Horizontal v =
    render . Lens.argument . layoutMode . modeWidths -~ v ^. View.size . _1

instance ( View.GluesTo (Aligned (Widget a)) (AlignTo b) (Aligned (Widget a))
         , View.HasSize b
         ) => View.Glue (TreeLayout a) (AlignTo b) where
    type Glued (TreeLayout a) (AlignTo b) = TreeLayout a
    glue orientation l v =
        l
        & adjustWidth orientation v
        & render . Lens.mapped %~ (View.glue orientation ?? v)

instance ( View.GluesTo (AlignTo a) (Aligned (Widget b)) (Aligned (Widget b))
         , View.HasSize a
         ) => View.Glue (AlignTo a) (TreeLayout b) where
    type Glued (AlignTo a) (TreeLayout b) = TreeLayout b
    glue orientation v l =
        l
        & adjustWidth orientation v
        & render . Lens.mapped %~ View.glue orientation v

instance View.SetLayers (TreeLayout a) where
    setLayers = Widget.widget . View.setLayers
    hoverLayers = Widget.widget %~ View.hoverLayers

instance Functor f => View.Resizable (TreeLayout (f Widget.EventResult)) where
    empty = TreeLayout (const View.empty)
    pad p w =
        w
        & render . Lens.argument . layoutMode . modeWidths -~ 2 * (p ^. _1)
        & render . Lens.mapped %~ View.pad p
    scale = error "TreeLayout: scale not Implemented"
    assymetricPad = error "TreeLayout: assymetricPad not implemented"

instance E.HasEventMap TreeLayout where eventMap = Widget.widget . E.eventMap

instance Widget.HasWidget TreeLayout where widget = alignedWidget . Align.value

alignedWidget ::
    Lens.Setter
    (TreeLayout a) (TreeLayout b)
    (Aligned (Widget a)) (Aligned (Widget b))
alignedWidget = render . Lens.mapped

alignment :: Lens.Setter' (TreeLayout a) (Vector2 R)
alignment = alignedWidget . Align.alignmentRatio

-- | Lifts a Widget into a 'TreeLayout'
fromAlignedWidget :: Aligned (Widget a) -> TreeLayout a
fromAlignedWidget = TreeLayout . const

-- | Lifts a Widget into a 'TreeLayout' with an alignment point at the top left
fromWidget :: Widget a -> TreeLayout a
fromWidget = fromAlignedWidget . Aligned 0

-- | Lifts a View into a 'TreeLayout' with an alignment point at the top left
fromView :: View -> TreeLayout a
fromView = fromWidget . Widget.fromView

-- | The empty 'TreeLayout'
empty :: TreeLayout a
empty = fromView View.empty

-- | Vertical box with the alignment point from the top widget
vbox ::
    Functor f =>
    [TreeLayout (f Widget.EventResult)] -> TreeLayout (f Widget.EventResult)
vbox [] = empty
vbox (gui:guis) =
    TreeLayout $
    \layoutParams ->
    let cp =
            LayoutParams
            { _layoutMode = layoutParams ^. layoutMode
            , _layoutContext = LayoutVertical
            }
    in
    (gui ^. render) cp : (guis ^.. traverse . render ?? cp)
    & View.vbox

vboxSpaced ::
    (MonadReader env m, Spacer.HasStdSpacing env, Functor f) =>
    m ([TreeLayout (f Widget.EventResult)] -> TreeLayout (f Widget.EventResult))
vboxSpaced =
    Spacer.stdVSpace
    <&> fromView
    <&> List.intersperse
    <&> Lens.mapped %~ vbox

-- TODO: We should get "WithTextPos" of Widgets when that exists.
-- TODO: In future this may have multiple layout options!
taggedList ::
    (MonadReader env m, Spacer.HasStdSpacing env, Functor f) =>
    m ([(Widget (f Widget.EventResult), TreeLayout (f Widget.EventResult))] -> TreeLayout (f Widget.EventResult))
taggedList =
    vboxSpaced <&>
    \box pairs ->
    let headerWidth = pairs ^.. traverse . _1 . View.width & maximum
        renderPair (header, treeLayout) =
            AlignTo 0 (View.assymetricPad (Vector2 (headerWidth - header ^. View.width) 0) 0 header)
            /|/ treeLayout
    in
    pairs <&> renderPair & box
    & alignment . _1 .~ 0 -- TODO: remove when no horizontal alignment
