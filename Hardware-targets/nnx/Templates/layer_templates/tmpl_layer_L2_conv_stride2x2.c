/*
 * layer_template_nnx.c
 * Francesco Conti <f.conti@unibo.it>
 * Alessio Burrello <alessio.burrello@unibo.it>
 * Luka Macan <luka.macan@unibo.it>
 *
 * Copyright (C) 2018-2022 University of Bologna
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

#include "${func_name}.h"
#include "pulp_nnx.h"
#include "pulp_nnx_util.h"
#include "network.h"
#include "dory_dma_v2.h"
#include "dory_get_tile.h"
#include "layer_debug.h"
#include "memory.h"
#include "tile_status.h"
#include "execute_stride2x2.h"

/* Defines
 *
 * 1. Debugging
 *    - DEBUG_GVSOC - enable gvsoc logging
 *    - DEBUG_TILE_CHECKSUM - calculate and print per-tile-checksum
 */

/////////////////
// Total tiles //
/////////////////

static void load_input_prepare(Layer tile, Layer body, Layer layer, TileIndex index, DmaTransferConf * const conf) {
    // additionally overlap by padding for the first tile after a border one
    // this because in the first tile we use less pixels from x_buffer, since we have the ones of padding
    const int x_offset_h = index.height > 0 ? layer.padding.top : 0;
    const int x_offset_w = index.width > 0 ? layer.padding.left : 0;

    conf->ext = (void *)dory_get_tile_3d(layer.addr.input,
                                   index.height, index.width, 0,
                                   body.input.height, body.input.width, body.input.channel,
                                   ${x_w}, ${nif*g},
                                   ${conv_overlap1}, ${conv_overlap2}, 0,
                                   x_offset_h, x_offset_w, 0,
                                   ${x_data_size_byte});
    conf->loc = (void *)tile.addr.input;
    conf->number_of_2d_copies = tile.input.height;
    conf->number_of_1d_copies = tile.input.width;
    conf->length_1d_copy = tile.input.channel;
}

static void load_input_async(DmaTransferConf conf, MemoryStatus * const status) {
    memory_transfer_async(conf, status);
}

static void store_output_prepare(Layer tile, Layer body, Layer layer, TileIndex index, DmaTransferConf * const conf) {
    conf->ext = (void *)dory_get_tile_3d(layer.addr.output,
                                         index.height, index.width, index.output_channel,
                                         body.output.height, body.output.width, body.output.channel,
                                         ${y_w}, ${int(nof*factor)},
                                         0, 0, 0,
                                         0, 0, 0,
                                         ${y_data_size_byte});
    conf->loc = (void *)tile.addr.output;
    conf->number_of_2d_copies = tile.output.height;
    conf->number_of_1d_copies = tile.output.width;
    conf->length_1d_copy = tile.output.channel;
}

static void store_output_async(DmaTransferConf conf, MemoryStatus * const status) {
    memory_transfer_async(conf, status);
}

static void load_weights_prepare(Layer tile, Kernel kernel,
                                 MemoryStatus status_weights,
                                 MemoryStatus status_scale,
                                 MemoryStatus status_bias,
                                 DmaTransferConf * const conf_weights,
                                 DmaTransferConf * const conf_scale,
                                 DmaTransferConf * const conf_bias
                                 ) {
    // Special because of accelerators special memory layout
    const int size_weights = (kernel.groups > 1 ? DIVNCEIL(tile.output.channel, 16) : tile.output.channel) * ${l1_W_tile_ki_size};
    const int size_scale = tile.output.channel * ${int(act_dim_bit/8)};
    const int size_bias = tile.output.channel * ${int(bias_bits/8)};

    #define CONF_SET(name)                                              ${"\\"}
        do {                                                            ${"\\"}
            if (status_ ## name.is_transfer) {                          ${"\\"}
                conf_ ## name->ext = (void *)status_ ## name.addr_ext;  ${"\\"}
                conf_ ## name->loc = (void *)tile.addr.name;            ${"\\"}
                conf_ ## name->length_1d_copy = size_ ## name;          ${"\\"}
            }                                                           ${"\\"}
        } while (0)

    CONF_SET(weights);
    CONF_SET(scale);
    CONF_SET(bias);
}

static void load_weights_async(DmaTransferConf conf_weights,
                               DmaTransferConf conf_scale,
                               DmaTransferConf conf_bias,
                               MemoryStatus * const status_weights,
                               MemoryStatus * const status_scale,
                               MemoryStatus * const status_bias) {
    #define MEMORY_TRANSFER_1D_ASYNC(name) ${"\\"}
        memory_transfer_1d_async(conf_ ## name, status_ ## name)

    MEMORY_TRANSFER_1D_ASYNC(weights);
    MEMORY_TRANSFER_1D_ASYNC(scale);
    MEMORY_TRANSFER_1D_ASYNC(bias);
}

void ${func_name}(void *args) {

    #ifdef DEBUG_GVSOC
    nnx_activate_gvsoc_logging(GVSOC_LOGGING_FORMAT_DECIMAL);
    #endif

    layer_args_t *layer_args = (layer_args_t *)args;
    const unsigned int l1_buffer = layer_args->L1_buffer;
    const unsigned int out_shift = layer_args->out_shift;

    const Layer layer = {
        .addr = {
            .input = layer_args->L2_input,
            .weights = layer_args->L2_weights,
            .scale = layer_args->L2_weights + ${l2_k_offset},
            .bias = layer_args->L2_weights + ${l2_lambda_offset},
            .output = layer_args->L2_output
        },
        .padding = {
            .top    = layer_args->padding & PAD_TOP ? ${padding_top} : DONT_PAD,
            .right  = ${padding_right},
            .bottom = layer_args->padding & PAD_BOTTOM ? ${padding_bottom} : DONT_PAD,
            .left   = ${padding_left}
        }
    };

    const Kernel kernel = {
        .shape = {
            .height = ${fs1},
            .width = ${fs2}
        },
        .stride = {
            .height = ${s[0]},
            .width = ${s[1]}
        },
        .groups = ${g}
    };

    const TileIndex end_index = {
        .height = ${tile_dim_h},
        .width = ${tile_dim_w},
        .output_channel = ${tile_dim_nof}
    };

    const Layer body = {
        .input = {
            .height = ${x_tile_size_h},
            .width = ${x_tile_size_w},
            .channel = ${x_tile_size_nif}
        },
        .output = {
            .height = ${y_tile_size_h},
            .width = ${y_tile_size_w},
            .channel = ${y_tile_size_nof}
        }
    };

    const Layer border = {
        .input = {
            .height = ${x_tile_size_h_last},
            .width = ${x_tile_size_w_last},
            .channel = ${x_tile_size_nif_last}
        },
        .output = {
            .height = ${y_tile_size_h_last},
            .width = ${y_tile_size_w_last},
            .channel = ${y_tile_size_nof_last}
        }
    };


    // Double buffer addresses init

    const int l1_buffer_x = l1_buffer + ${l1_x_offset};
    const int l1_buffer_y = l1_buffer + ${l1_y_offset};
    const int l1_buffer_w = l1_buffer + ${l1_W_offset};
    const int l1_buffer_scale = l1_buffer + ${l1_k_offset};
    const int l1_buffer_bias = l1_buffer + ${l1_lambda_offset};

    Address double_buffer_addresses[2] = {
      {
        .input = l1_buffer_x,
        .weights = l1_buffer_w,
        .scale = l1_buffer_scale,
        .bias = l1_buffer_bias,
        .output = l1_buffer_y
      },
      {
        .input = l1_buffer_x + ${l1_x_tile_size},
        .weights = l1_buffer_w + ${l1_W_tile_size},
        .scale = l1_buffer_scale + ${l1_k_tile_size},
        .bias = l1_buffer_bias + ${l1_lambda_tile_size},
        .output = l1_buffer_y + ${l1_y_tile_size}
      }
    };

    // Variable declaration
    
    DmaTransferConf conf_input = {
        .stride_2d = ${l1_x_dma_stride_2d},
        .stride_1d = ${l1_x_dma_stride_1d},
        .dir = 1
    };
    DmaTransferConf conf_weights = { .dir = 1 };
    DmaTransferConf conf_scale = { .dir = 1 };
    DmaTransferConf conf_bias = { .dir = 1 };
    DmaTransferConf conf_output = {
        .stride_2d = ${l1_y_dma_stride_2d},
        .stride_1d = ${l1_y_dma_stride_1d},
        .dir = 0
    };

    #define MEMORY_STATUS_INIT(name)     ${"\\"}
        .name = {                        ${"\\"}
            .addr_ext = layer.addr.name, ${"\\"}
            .is_wait = 0,                ${"\\"}
            .is_transfer = 1,            ${"\\"}
            .buffer_index = 0            ${"\\"}
        }

    TileStatus tile_status = {
        .index = { 0 },
        .memory_status = {
            MEMORY_STATUS_INIT(input),
            MEMORY_STATUS_INIT(weights),
            MEMORY_STATUS_INIT(scale),
            MEMORY_STATUS_INIT(bias),
            MEMORY_STATUS_INIT(output)
        }
    };

    Layer tile = tile_create(tile_status.index, end_index, body, border, layer,
                             tile_status_get_addr(tile_status, double_buffer_addresses));

    load_input_prepare(tile, body, layer, tile_status.index,
                       &conf_input);
    load_input_async(conf_input, &tile_status.memory_status.input);

    load_weights_prepare(tile, kernel,
                         tile_status.memory_status.weights,
                         tile_status.memory_status.scale,
                         tile_status.memory_status.bias,
                         &conf_weights,
                         &conf_scale,
                         &conf_bias);

    load_weights_async(conf_weights,
                       conf_scale,
                       conf_bias,
                       &tile_status.memory_status.weights,
                       &tile_status.memory_status.scale,
                       &tile_status.memory_status.bias);


    // Accelerator init

    nnx_init();

    nnx_task_t task = nnx_task_create(
            ${fs1}, ${int(flag_DW)},
            ${x_data_size_byte}, ${y_data_size_byte}, ${W_data_size},
            weightOffsetModeLayerWise, ${-(2**(W_data_size-1))},
            (nnx_quant_t) {
                .shift_amount = out_shift,
                .mode = quantMode8Bit,
                .function = quantFunctionRelu,
                .flag_rounding = FLAG_UNUSED
            }, (nnx_norm_t) {
                .mode  = ${"normMode32Bit" if act_dim_bit == 32 else "normMode8Bit" if act_dim_bit == 8 else "FLAG_UNUSED"},
                .flag_bias  = FLAG_USED,
                .flag_shift = FLAG_UNUSED
            }, ${stride});


    // Tile loop
    TileStatus tile_status_next;
    Layer tile_next;

    const int total_tiles = end_index.height * end_index.width * end_index.output_channel;

    if (total_tiles > 1) {
        tile_status_next = tile_status_get_next(tile_status, end_index);
        tile_next = tile_create(tile_status_next.index, end_index, body, border, layer,
                                tile_status_get_addr(tile_status_next, double_buffer_addresses));
    }

    for (int i_tile = 0; i_tile < total_tiles; i_tile++) {
        if (i_tile + 1 < total_tiles) {

            if (tile_status_next.memory_status.input.is_transfer) {
                load_input_prepare(tile_next, body, layer, tile_status_next.index,
                                   &conf_input);

                load_input_async(conf_input, &tile_status_next.memory_status.input);
            }

            load_weights_prepare(tile_next, kernel,
                                 tile_status_next.memory_status.weights,
                                 tile_status_next.memory_status.scale,
                                 tile_status_next.memory_status.bias,
                                 &conf_weights,
                                 &conf_scale,
                                 &conf_bias);

            load_weights_async(conf_weights,
                               conf_scale,
                               conf_bias,
                               &tile_status_next.memory_status.weights,
                               &tile_status_next.memory_status.scale,
                               &tile_status_next.memory_status.bias);
        }

        execute_stride2x2_prepare(tile, kernel, &task);

        tile_memory_wait(&tile_status);

        execute_stride2x2_blocking(task, tile, kernel);

        store_output_prepare(tile, body, layer, tile_status.index, &conf_output);

        tile = tile_next;
        tile_status = tile_status_next;
            
        if (i_tile + 1 < total_tiles) {
            tile_status_next = tile_status_get_next(tile_status, end_index);
            tile_next = tile_create(tile_status_next.index, end_index, body, border, layer,
                                    tile_status_get_addr(tile_status_next, double_buffer_addresses));
        }
        
        execute_stride2x2_wait();

        store_output_async(conf_output, &tile_status.memory_status.output);
    }

    memory_wait(&tile_status_next.memory_status.output);
    nnx_term();
}
