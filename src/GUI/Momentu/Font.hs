{-# LANGUAGE TemplateHaskell, RecordWildCards #-}
-- | A font attached to its size

module GUI.Momentu.Font
    ( Underline(..), underlineColor, underlineWidth
    , render
    , DrawUtils.TextSize(..)
    , DrawUtils.textSize
    , height
    ) where

import qualified Control.Lens as Lens
import           Data.Vector.Vector2 (Vector2(..))
import           Graphics.DrawingCombinators ((%%))
import qualified Graphics.DrawingCombinators as Draw
import           Graphics.DrawingCombinators.Utils (TextSize(..))
import qualified Graphics.DrawingCombinators.Utils as DrawUtils

import           Lamdu.Prelude

data Underline = Underline
    { _underlineColor :: Draw.Color
    , _underlineWidth :: Draw.R
    }
Lens.makeLenses ''Underline

height :: Draw.Font -> Draw.R
height = DrawUtils.fontHeight

render ::
    Draw.Font -> Draw.Color -> Maybe Underline -> Text ->
    (TextSize (Vector2 Draw.R), Draw.Image ())
render font color mUnderline str =
    ( size
    , DrawUtils.drawText font attrs str
      <> maybe mempty (drawUnderline font (DrawUtils.bounding size)) mUnderline
    )
    where
        attrs =
            Draw.defTextAttrs
            { Draw.gamma = 1.0
            , Draw.foregroundColor = color
            }
        size = DrawUtils.textSize font str

drawUnderline :: Draw.Font -> Vector2 Draw.R -> Underline -> Draw.Image ()
drawUnderline font size (Underline color relativeWidth) =
    DrawUtils.square
    & (DrawUtils.scale (Vector2 (size ^. _1) width) %%)
    & (DrawUtils.translate (Vector2 0 (size ^. _2 + descender + width/2)) %%)
    & Draw.tint color
    where
        width = relativeWidth * height font
        descender = Draw.fontDescender font