infixr 4 %%@~, <%@~, %%~, <+~, <*~, <-~, <//~, <^~, <^^~, <**~
infix 4 %%@=, <%@=, %%=, <+=, <*=, <-=, <//=, <^=, <^^=, <**=
infixr 2 <<~
infixr 9 #.
infixl 8 .#
infixr 8 ^!, ^@!
infixl 1 &, <&>, ??
infixl 8 ^., ^@.
infixr 9 <.>, <., .>
infixr 4 %@~, .~, +~, *~, -~, //~, ^~, ^^~, **~, &&~, <>~, ||~, %~
infix 4 %@=, .=, +=, *=, -=, //=, ^=, ^^=, **=, &&=, <>=, ||=, %=
infixr 2 <~
infixr 2 `zoom`, `magnify`
infixl 8 ^.., ^?, ^?!, ^@.., ^@?, ^@?!
infixl 8 ^#
infixr 4 <#~, #~, #%~, <#%~, #%%~
infix 4 <#=, #=, #%=, <#%=, #%%=
infixl 9 :>
infixr 4 </>~, <</>~, <.>~, <<.>~
infix 4 </>=, <</>=, <.>=, <<.>=
infixr 4 .|.~, .&.~, <.|.~, <.&.~
infix 4 .|.=, .&.=, <.|.=, <.&.=

warn = a .~ Just b ==> a ?~ b
warn = a & Control.Lens.mapped %~ b ==> a <&> b
warn = a & Control.Lens.mapped . b %~ c ==> a <&> b %~ c
