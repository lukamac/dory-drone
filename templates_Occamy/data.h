/*
 * dory.h
 * Alessio Burrello <alessio.burrello@unibo.it>
 *
 * Copyright (C) 2019-2020 University of Bologna
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 */

% for layer_name, layer_weights, layer_weights_for_len in zip(weights_layers_names, weight_layers, weight_layers_for_dim):
static float ${layer_name}[${len(layer_weights_for_len)}]={${layer_weights}};
% endfor

static float input[${input_len}]={${input}};
static float l2_zeros[128*128*64] = {0};