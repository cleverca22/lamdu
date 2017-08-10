{-# LANGUAGE NoImplicitPrelude, DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
module GUI.Momentu.Widgets.StdKeys (DirKeys(..), stdDirKeys) where

import qualified Graphics.UI.GLFW as GLFW

import           Lamdu.Prelude

data DirKeys key = DirKeys
    { keysLeft, keysRight, keysUp, keysDown :: [key]
    } deriving (Functor, Foldable, Traversable)

stdDirKeys :: DirKeys GLFW.Key
stdDirKeys = DirKeys
    { keysLeft  = [GLFW.Key'Left,  GLFW.Key'H]
    , keysRight = [GLFW.Key'Right, GLFW.Key'L]
    , keysUp    = [GLFW.Key'Up,    GLFW.Key'K]
    , keysDown  = [GLFW.Key'Down,  GLFW.Key'J]
    }