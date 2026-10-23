import "package:flutter/material.dart";
import "package:flutter/semantics.dart";

void announce(BuildContext context, String words,
        {Assertiveness assertiveness = Assertiveness.polite}) =>
    SemanticsService.announce(words, Directionality.of(context),
        assertiveness: assertiveness);
