# Grab mouse button codes
# xev | grep button

# Example.
# Page forward => state 0x0, button 9, same_screen YES
# Page back => state 0x0, button 8, same_screen YES

# Grab keyboard codes
# xev | grep 

# Example.
# Ctrl-C
# KeyPress event, serial 37, synthetic NO, window 0x3400001,
#     root 0x6cb, subw 0x0, time 419655768, (42,124), root:(2816,457),
#     state 0x0, keycode 37 (keysym 0xffe3, Control_L), same_screen YES,
#     XLookupString gives 0 bytes: 
#     XmbLookupString gives 0 bytes: 
#     XFilterEvent returns: False
# KeyPress event, serial 37, synthetic NO, window 0x3400001,
#     root 0x6cb, subw 0x0, time 419656127, (42,124), root:(2816,457),
#     state 0x4, keycode 54 (keysym 0x63, c), same_screen YES,
#     XLookupString gives 1 bytes: (03) ""
#     XmbLookupString gives 1 bytes: (03) ""
#     XFilterEvent returns: False

# Ctrl-V
# KeyPress event, serial 37, synthetic NO, window 0x3400001,
#     root 0x6cb, subw 0x0, time 419657289, (42,124), root:(2816,457),
#     state 0x0, keycode 37 (keysym 0xffe3, Control_L), same_screen YES,
#     XLookupString gives 0 bytes: 
#     XmbLookupString gives 0 bytes: 
#     XFilterEvent returns: False

# KeyPress event, serial 37, synthetic NO, window 0x3400001,
#     root 0x6cb, subw 0x0, time 419657589, (42,124), root:(2816,457),
#     state 0x4, keycode 55 (keysym 0x76, v), same_screen YES,
#     XLookupString gives 1 bytes: (16) ""
#     XmbLookupString gives 1 bytes: (16) ""
#     XFilterEvent returns: False

# xbindkeys -d > $HOME/.xbindkeysrc

# Starts up automatically on startup