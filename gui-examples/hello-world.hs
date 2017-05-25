{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}

module Main where

import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Data.MRUMemo (memoIO)
import           Data.Vector.Vector2 (Vector2(..))
import qualified Graphics.DrawingCombinators as Draw
import qualified Graphics.UI.Bottle.Main as Main
import           Graphics.UI.Bottle.Widget (Widget, Size, EventResult, strongerEvents, respondToCursor)
import qualified Graphics.UI.Bottle.Widgets.TextView as TextView
import           Graphics.UI.Bottle.Zoom (Zoom)
import qualified Graphics.UI.Bottle.Zoom as Zoom
import qualified Graphics.UI.GLFW.Utils as GLFWUtils

import           Prelude.Compat

fontPath :: FilePath
fontPath = "fonts/DejaVuSans.ttf"

main :: IO ()
main =
    do
        win <- GLFWUtils.createWindow "Hello World" Nothing (Vector2 800 400)
        cachedOpenFont <-
            memoIO $ \size ->
            Draw.openFont (min 100 (realToFrac (size ^. _2))) fontPath
        Main.defaultOptions fontPath
            >>= Main.mainLoopWidget win (hello cachedOpenFont)
    & GLFWUtils.withGLFW

hello ::
    Functor m =>
    (Size -> IO Draw.Font) -> Zoom -> Size -> IO (Widget (m EventResult))
hello getFont zoom _size =
    do
        sizeFactor <- Zoom.getSizeFactor zoom
        font <- getFont (sizeFactor * 20)
        TextView.makeWidget (TextView.whiteText font) "Hello World!" ["hello"]
            & respondToCursor
            & strongerEvents Main.quitEventMap
            & return
