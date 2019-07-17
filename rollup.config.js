import coffee from 'rollup-plugin-coffee-script';
import { uglify } from 'rollup-plugin-uglify';
import _ from 'lodash';

import pkg from './package.json';

const baseConfig = {
  input: 'lib/oms.coffee',
  output: {
    file: 'build/oms.js',
    format: 'iife',
    name: 'OverlappingMarkerSpiderfier'
  },
  plugins: [
    coffee()
  ],
  context: 'window'
};

export default [
  baseConfig,
  _.merge(_.cloneDeep(baseConfig), {
    output: {
      file: pkg.main
    },
    plugins: [
      uglify()
    ]
  })
];
