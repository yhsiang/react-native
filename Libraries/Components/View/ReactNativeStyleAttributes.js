/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 * @providesModule ReactNativeStyleAttributes
 * @flow
 */

'use strict';

var NativeModules = require('NativeModules');
var ImageStylePropTypes = require('ImageStylePropTypes');
var TextStylePropTypes = require('TextStylePropTypes');
var ViewStylePropTypes = require('ViewStylePropTypes');
var Platform = require('Platform');

var keyMirror = require('fbjs/lib/keyMirror');
var matricesDiffer = require('matricesDiffer');
var processColor = require('processColor');
var processTransform = require('processTransform');
var sizesDiffer = require('sizesDiffer');

var ReactNativeStyleAttributes = {
  ...keyMirror(ViewStylePropTypes),
  ...keyMirror(TextStylePropTypes),
  ...keyMirror(ImageStylePropTypes),
};

ReactNativeStyleAttributes.transform = { process: processTransform };
ReactNativeStyleAttributes.transformMatrix = { diff: matricesDiffer };
ReactNativeStyleAttributes.shadowOffset = { diff: sizesDiffer };

// Do not rely on this attribute.
ReactNativeStyleAttributes.decomposedMatrix = 'decomposedMatrix';

let PlatformFonts = NativeModules.ExponentConstants.systemFonts;

if (Platform.OS === 'ios') {
  PlatformFonts = [
    ...PlatformFonts,
    "Academy Engraved LET",
    "Al Nile",
    "American Typewriter",
    "Apple Color Emoji",
    "Apple SD Gothic Neo",
    "Arial",
    "Arial Hebrew",
    "Arial Rounded MT Bold",
    "Avenir",
    "Avenir Next",
    "Avenir Next Condensed",
    "Bangla Sangam MN",
    "Baskerville",
    "Bodoni Ornaments",
    "Bodoni 72",
    "Bodoni 72 Oldstyle",
    "Bodoni 72 Smallcaps",
    "Bradley Hand",
    "Chalkboard SE",
    "Chalkduster",
    "Cochin",
    "Copperplate",
    "Courier",
    "Courier New",
    "DB LCD Temp",
    "DIN Alternate",
    "DIN Condensed",
    "Damascus",
    "Devanagari Sangam MN",
    "Didot",
    "Diwan Mishafi",
    "Euphemia UCAS",
    "Farah",
    "Futura",
    "Geeza Pro",
    "Georgia",
    "Gill Sans",
    "Gujarati Sangam MN",
    "Gurmukhi MN",
    "Heiti SC",
    "Heiti TC",
    "Helvetica",
    "Helvetica Neue",
    "Hiragino Kaku Gothic ProN",
    "Hiragino Mincho ProN",
    "Hiragino Sans",
    "Hoefler Text",
    "Iowan Old Style",
    "Kailasa",
    "Kannada Sangam MN",
    "KhmerSangamMN",
    "Kohinoor Bangla",
    "KohinoorDevanagari",
    "Kohinor Telugu",
    "LaoSangamMN",
    "Malayalam Sangam MN",
    "Menlo",
    "Marion",
    "Marker Felt",
    "Noteworthy",
    "Optima",
    "Oriya Sangam MN",
    "Palatino",
    "Papyrus",
    "Party LET",
    "PingFang HK",
    "PingFang SC",
    "PingFang TC",
    "San Francisco",
    "Savoye Let",
    "Sinhala Sangam MN",
    "Snell Roundhand",
    "Superclarendon",
    "Symbol",
    "Tamil Sangam MN",
    "Telugu Sangam MN",
    "Thonburi",
    "Times New Roman",
    "Trebuchet MS",
    "Verdana",
    "Zapf Dingbats",
    "Zapfino",
    "System",
  ];
}

function processFontFamily(name) {
  const sessionId = NativeModules.ExponentConstants.sessionId;

  if (!name || PlatformFonts.indexOf(name) >= 0) {
    return name;
  }

  if (name.indexOf(sessionId) > -1) {
    return name;
  } else {
    return `ExponentFont-${sessionId}-${name}`;
  }
}

ReactNativeStyleAttributes.fontFamily = { process: processFontFamily };

var colorAttributes = { process: processColor };
ReactNativeStyleAttributes.backgroundColor = colorAttributes;
ReactNativeStyleAttributes.borderBottomColor = colorAttributes;
ReactNativeStyleAttributes.borderColor = colorAttributes;
ReactNativeStyleAttributes.borderLeftColor = colorAttributes;
ReactNativeStyleAttributes.borderRightColor = colorAttributes;
ReactNativeStyleAttributes.borderTopColor = colorAttributes;
ReactNativeStyleAttributes.color = colorAttributes;
ReactNativeStyleAttributes.shadowColor = colorAttributes;
ReactNativeStyleAttributes.textDecorationColor = colorAttributes;
ReactNativeStyleAttributes.tintColor = colorAttributes;
ReactNativeStyleAttributes.textShadowColor = colorAttributes;
ReactNativeStyleAttributes.overlayColor = colorAttributes;

module.exports = ReactNativeStyleAttributes;
