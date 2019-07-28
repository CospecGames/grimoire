/**
    Include all the standard library.

    Copyright: (c) Enalye 2018
    License: Zlib
    Authors: Enalye
*/

module grimoire.stdlib;

import grimoire.compiler;

import grimoire.stdlib.array;
import grimoire.stdlib.print;
import grimoire.stdlib.random;
import grimoire.stdlib.test;
import grimoire.stdlib.time;
import grimoire.stdlib.typecast;

void grLoadStdLibrary() {
    grLoadStdLibArray();
    grLoadStdLibPrint();
    grLoadStdLibRandom();
    grLoadStdLibTest();
    grLoadStdLibTime();
    grLoadStdLibTypecast();
}