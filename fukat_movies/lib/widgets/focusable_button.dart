import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FocusableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final BoxDecoration? defaultDecoration;
  final BoxDecoration? focusedDecoration;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final double scaleFactor;

  const FocusableButton({
    Key? key,
    required this.child,
    required this.onTap,
    this.defaultDecoration,
    this.focusedDecoration,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.scaleFactor = 1.05,
  }) : super(key: key);

  @override
  State<FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<FocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    // Global standard for TV focus if custom ones aren't provided
    final defDec = widget.defaultDecoration ?? BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.transparent, width: 3),
    );

    final focDec = widget.focusedDecoration ?? BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.redAccent, width: 3),
      boxShadow: [
        BoxShadow(
          color: Colors.redAccent.withOpacity(0.6),
          blurRadius: 12,
          spreadRadius: 2,
        )
      ],
    );

    return Container(
      margin: widget.margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.select || 
                    key == LogicalKeyboardKey.enter || 
                    key == LogicalKeyboardKey.space || 
                    key == LogicalKeyboardKey.numpadEnter) {
                  widget.onTap();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: AnimatedScale(
              scale: _isFocused ? widget.scaleFactor : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: widget.padding,
                decoration: _isFocused ? focDec : defDec,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
