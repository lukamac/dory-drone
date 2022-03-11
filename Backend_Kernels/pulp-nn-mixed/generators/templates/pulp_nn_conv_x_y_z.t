/*
 * ${config.filename}
 * Nazareno Bruschi <nazareno.bruschi@unibo.it>
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

#include "pmsis.h"
#include "pulp_nn_utils.h"
#include "pulp_nn_kernels.h"


void ${config.fn_name}(
                        uint8_t *pIn,
                        uint8_t *pIm2ColBuffer,
                        int8_t *pBias,
                        uint8_t *pOut,
                        int8_t *pWeight,
%if config.kernel.act_prec == '32bit':
                        int32_t *pKappa,
                        int32_t *pLambda,
%elif config.kernel.act_prec == '64bit':
                        int64_t *pKappa,
                        int64_t *pLambda,
%endif
                        uint16_t out_mult,
                        uint16_t out_shift,
                        uint16_t dim_in_x,
                        uint16_t dim_in_y,
                        uint16_t ch_in,
                        uint16_t dim_out_x,
                        uint16_t dim_out_y,
                        uint16_t ch_out,
                        uint16_t dim_kernel_x,
                        uint16_t dim_kernel_y,
                        uint16_t padding_y_top,
                        uint16_t padding_y_bottom,
                        uint16_t padding_x_left,
                        uint16_t padding_x_right,
                        uint16_t stride_x,
                        uint16_t stride_y,
                        uint8_t flag_relu,
                        uint8_t flag_batch_norm)
{
%if config.kernel.in_data_t == 8:
  uint16_t ch_in_r = ch_in;
%elif config.kernel.in_data_t == 4:
  uint16_t ch_in_r = ch_in >> 1;
%else:
  uint16_t ch_in_r = ch_in >> 2;
%endif
%if config.kernel.out_data_t == 8:
  uint16_t ch_out_r = ch_out;
%elif config.kernel.out_data_t == 4:
  uint16_t ch_out_r = ch_out >> 1;
%else:
  uint16_t ch_out_r = ch_out >> 2;
%endif

  int core_id = pi_core_id();
  uint8_t * pIm2ColBase = pIm2ColBuffer + (2 * core_id * ch_in * dim_kernel_x * dim_kernel_y);
  int i_out_y, i_out_x, i_ker_y, i_ker_x;
  int Log2Core;

  uint8_t extra_chunk = ((dim_out_y & (NUM_CORES-1)) != 0);
  uint8_t extra_chunk_r;
  uint16_t dim_out_x_r;
  uint8_t section;
  int core_id_r;

  if(extra_chunk && dim_out_x > 1)
  {
    Log2Core = log2(NUM_CORES >> 1);
    core_id_r = (core_id >> 1);
    dim_out_x_r = (dim_out_x >> 1);
    section = (core_id & 0x1);
    extra_chunk_r = ((dim_out_y & ((NUM_CORES >> 1) - 1)) != 0);
  }
  else
  {
    Log2Core = log2(NUM_CORES);
    core_id_r = core_id;
    dim_out_x_r = dim_out_x;
    section = 0;
    extra_chunk_r = extra_chunk;
    extra_chunk = 0;
  }

  uint8_t flag_dim_out_x_odd = dim_out_x & 0x01;

  int chunk = (dim_out_y >> Log2Core) + extra_chunk_r;

  int start_pixel = min((chunk * core_id_r), dim_out_y);
  int stop_pixel = min(start_pixel + chunk, dim_out_y);

  uint8_t *pIm2Col = pIm2ColBase;
  uint8_t *pOutBuffer = pOut + (start_pixel * ch_out_r * dim_out_x) + (section * ch_out_r * dim_out_x_r);

  for (i_out_y = start_pixel; i_out_y < stop_pixel; i_out_y++)
  {
    for(i_out_x=(section * dim_out_x_r); i_out_x<(dim_out_x_r + (section * (dim_out_x_r + flag_dim_out_x_odd))); i_out_x++)
    {
      if(i_out_y < padding_y_top)
      {
        for(i_ker_y=((i_out_y * stride_y) - padding_y_top); i_ker_y<((i_out_y * stride_y) - padding_y_top + dim_kernel_y); i_ker_y++)
        {
          for(i_ker_x=((i_out_x * stride_x) - padding_x_left); i_ker_x<((i_out_x * stride_x) - padding_x_left + dim_kernel_x); i_ker_x++)
          {
            if((i_ker_y < 0) || (i_ker_y >= dim_in_y) || (i_ker_x < 0) || (i_ker_x >= dim_in_x))
            {
              pulp_zero_mem(pIm2Col, ch_in);
            }
            else
            {
              ${config.im2col_fn}((uint8_t*) (pIn + ((i_ker_y * dim_in_x + i_ker_x) * ch_in_r)), pIm2Col, ch_in);
            }
            pIm2Col+=ch_in;
          }
        }
      }
      else if(i_out_y < dim_out_y - padding_y_bottom)
      {
        if(i_out_x < padding_x_left)
        {
          for(i_ker_y=((i_out_y * stride_y) - padding_y_top); i_ker_y<((i_out_y * stride_y) - padding_y_top + dim_kernel_y); i_ker_y++)
          {
            for(i_ker_x=((i_out_x * stride_x) - padding_x_left); i_ker_x<((i_out_x * stride_x) - padding_x_left + dim_kernel_x); i_ker_x++)
            {
              if((i_ker_x < 0) || (i_ker_x >= dim_in_x))
              {
                pulp_zero_mem(pIm2Col, ch_in);
              }
              else
              {
                ${config.im2col_fn}((uint8_t*) (pIn + ((i_ker_y * dim_in_x + i_ker_x) * ch_in_r)), pIm2Col, ch_in);
              }
              pIm2Col+=ch_in;
            }
          }
        }
        else if(i_out_x < (dim_out_x - padding_x_right))
        {
          for(i_ker_y=((i_out_y * stride_y) - padding_y_top); i_ker_y<((i_out_y * stride_y) - padding_y_top + dim_kernel_y); i_ker_y++)
          {
            ${config.im2col_fn}((uint8_t*) pIn + (i_ker_y * dim_in_x + i_out_x * stride_x - padding_x_left)*ch_in_r,pIm2Col,ch_in * dim_kernel_x);
            pIm2Col+=(ch_in * dim_kernel_x);
          }
        }
        else
        {
          for(i_ker_y=((i_out_y * stride_y) - padding_y_top); i_ker_y<((i_out_y * stride_y) - padding_y_top + dim_kernel_y); i_ker_y++)
          {
            for(i_ker_x = i_out_x * stride_x - padding_x_left; i_ker_x < i_out_x * stride_x - padding_x_left + dim_kernel_x; i_ker_x++)
            {
              if((i_ker_x < 0) || (i_ker_x >= dim_in_x))
              {
                pulp_zero_mem(pIm2Col, ch_in);
              }
              else
              {
                ${config.im2col_fn}((uint8_t *)pIn + (i_ker_y*dim_in_x+i_ker_x)* ch_in_r, pIm2Col, ch_in);
              }
              pIm2Col+=ch_in;
            }
          }
        }
      }
      else
      {
        for(i_ker_y=((i_out_y * stride_y) - padding_y_top); i_ker_y<((i_out_y * stride_y) - padding_y_top + dim_kernel_y); i_ker_y++)
        {
          for(i_ker_x = i_out_x * stride_x - padding_x_left; i_ker_x < i_out_x * stride_x - padding_x_left + dim_kernel_x; i_ker_x++)
          {
            if(i_ker_y < 0 || (i_ker_y >= dim_in_y) || i_ker_x < 0 || i_ker_x >= dim_in_x)
            {
              pulp_zero_mem(pIm2Col, ch_in);
            }
            else
            {
              ${config.im2col_fn}((uint8_t *) pIn + (i_ker_y * dim_in_x + i_ker_x) * ch_in_r, pIm2Col, ch_in);
            }
            pIm2Col+=ch_in;
          }
        }
      }
      if(pIm2Col == (pIm2ColBase + ((ch_in * dim_kernel_x * dim_kernel_y) << 1)))
      {
        pOutBuffer = ${config.mat_mul_fn}(
          pIm2ColBase,
          pBias,
          pOutBuffer,
          pOutBuffer + ch_out_r,
          pWeight,
          pKappa,
          pLambda,
          out_mult,
          out_shift,
          (ch_in * dim_kernel_x * dim_kernel_y),
          ch_out,
          flag_relu,
          flag_batch_norm
          );

        pIm2Col = pIm2ColBase;
      }
    }
  //   pOut+=(extra_chunk * ((dim_out_x_r + ((1 - section) * flag_dim_out_x_odd)) * ch_out_r));
  // }

    if(pIm2Col != pIm2ColBase)
    {
  %if config.kernel.out_data_t == 2:
      int8_t mask2 = 0x0c;
      int8_t n_mask2 = ~ mask2;
      int8_t mask4 = 0x30;
      int8_t n_mask4 = ~ mask4;
      int8_t mask6 = 0xc0;
      int8_t n_mask6 = ~ mask6;
      int8_t off2 = 2;
      int8_t off4 = 4;
      int8_t off6 = 6;
  %elif config.kernel.out_data_t == 4:
      int8_t mask = 0xf0;
      int8_t n_mask = ~ mask;
      int8_t off = 0x04;
  %endif
      const int8_t *pA = pWeight;
      int i;
%if config.kernel.act_prec == '32bit':
      int32_t * k1 = pKappa;
      int32_t * lambda1 = pLambda;
%elif config.kernel.act_prec == '64bit':
      int64_t * k1 = pKappa;
      int64_t * lambda1 = pLambda;
%endif
  %if config.kernel.wt_data_t == 2:
      v4s inA[4];
      v4u inB;
  %elif config.kernel.wt_data_t == 4:
      v4s inA[2];
      v4u inB;
  %endif
  %if config.kernel.out_data_t == 4:
      uint8_t out[2];
  %elif config.kernel.out_data_t == 2:
      uint8_t out[4];
  %endif
      for(i = 0; i < ch_out; i++)
      {
        int sum = 0;
        if (pBias != NULL)
        {
          sum = ((int) (*pBias++));
        }

        uint8_t *pB = pIm2ColBase;
  %if config.kernel.wt_data_t == 8:
        uint16_t col_cnt_im2col = ch_in * dim_kernel_x * dim_kernel_y >> 2;
  %elif config.kernel.wt_data_t == 4:
        uint16_t col_cnt_im2col = ch_in * dim_kernel_x * dim_kernel_y >> 3;
  %elif config.kernel.wt_data_t == 2:
        uint16_t col_cnt_im2col = ch_in * dim_kernel_x * dim_kernel_y >> 4;
  %endif
        for(int j=0; j < col_cnt_im2col; j++)
        {
  %if config.kernel.wt_data_t == 2:
          inB = *((v4u*) pB);

          pB+=4;

          pA = ${config.unpack_fn}(pA,inA);

          sum = SumDotp4(inB, inA[0], sum);

          inB = *((v4u*) pB);

          pB+=4;

          sum = SumDotp4(inB, inA[1], sum);

          inB = *((v4u*) pB);

          pB+=4;

          sum = SumDotp4(inB, inA[2], sum);

          inB = *((v4u*) pB);

          pB+=4;

          sum = SumDotp4(inB, inA[3], sum);
  %elif config.kernel.wt_data_t == 4:
          inB = *((v4u*) pB);

          pB+=4;

          pA = ${config.unpack_fn}(pA,inA);

          sum = SumDotp4(inB, inA[0], sum);

          inB = *((v4u*) pB);

          sum = SumDotp4(inB, inA[1], sum);

          pB+=4;
  %else:
          v4s inA = *((v4s*) pA);
          v4u inB = *((v4u*) pB);

          sum = SumDotp4(inB, inA, sum);
          pA+=4;
          pB+=4;
  %endif
        }
  %if config.kernel.wt_data_t == 2:
        col_cnt_im2col = (ch_in * dim_kernel_y * dim_kernel_x) & 0xf;
  %elif config.kernel.wt_data_t == 4:
        col_cnt_im2col = (ch_in * dim_kernel_y * dim_kernel_x) & 0x7;
  %else:
        col_cnt_im2col = (ch_in * dim_kernel_y * dim_kernel_x) & 0x3;
  %endif
        while (col_cnt_im2col)
        {
  %if config.kernel.wt_data_t == 2:
          int8_t inA1 = (int8_t) bitext((int) *pA, 2, 0);
          uint8_t inB1 = *pB++;
          sum += inA1 * inB1;
          inA1 = (int8_t) bitext((int) *pA, 2, 2);
          inB1 = *pB++;
          sum += inA1 * inB1;
          inA1 = (int8_t) bitext((int) *pA, 2, 4);
          inB1 = *pB++;
          sum += inA1 * inB1;
          inA1 = (int8_t) bitext((int) *pA, 2, 6);
          inB1 = *pB++;
          sum += inA1 * inB1;

          pA++;
          col_cnt_im2col-=4;
  %elif config.kernel.wt_data_t == 4:
          int8_t inA1 = (int8_t) bitext((int) *pA, 4, 0);
          uint8_t inB1 = *pB++;
          sum += inA1 * inB1;
          inA1 = (int8_t) bitext((int) *pA, 4, 4);
          inB1 = *pB++;
          sum += inA1 * inB1;

          pA++;
          col_cnt_im2col-=2;
  %else:
          int8_t inA1 = *pA++;
          uint8_t inB1 = *pB++;
          asm volatile("": : :"memory");
          sum += inA1 * inB1;

          col_cnt_im2col--;
  %endif
        }
  %if config.kernel.out_data_t == 8 or config.kernel.quantization == 'shift_clip':
        if (flag_batch_norm && flag_relu)
        {
  %if config.kernel.out_data_t == 8:
          *pOutBuffer = ${config.bn_fn}(sum, *k1, *lambda1, out_shift);
          k1++;
          lambda1++;
          pOutBuffer++;
  %elif config.kernel.out_data_t == 4:
          uint8_t i_o = i & 0x01;
          out[i_o] = ${config.bn_fn}(sum, *k1, *lambda1, out_shift);
          k1++;
          lambda1++;
          if(i_o == 0x01)
          {
            *pOutBuffer = bitins(out[0], n_mask, out[1], mask, off);
            pOutBuffer++;
          }
  %elif config.kernel.out_data_t == 2:
          uint8_t i_o = i & 0x03;
          out[i_o] = ${config.bn_fn}(sum, *k1, *lambda1, out_shift);
          k1++;
          lambda1++;
          if(i_o == 0x03)
          {
            out[0] = bitins(out[0], n_mask2, out[1], mask2, off2);
            out[0] = bitins(out[0], n_mask4, out[2], mask4, off4);
            *pOutBuffer = bitins(out[0], n_mask6, out[3], mask6, off6);
            pOutBuffer++;
          }
  %endif
        }
        else
        {
          if(flag_relu == 1)
          {
  %if config.kernel.out_data_t == 8:
            *pOutBuffer = ${config.relu_fn}(sum, out_mult, out_shift);
            pOutBuffer++;
  %elif config.kernel.out_data_t == 4:
            uint8_t i_o = i & 0x01;
            out[i_o] = ${config.relu_fn}(sum, out_mult, out_shift);
            if(i_o == 0x01)
            {
              *pOutBuffer = bitins(out[0], n_mask, out[1], mask, off);
              pOutBuffer++;
            }
  %elif config.kernel.out_data_t == 2:
            uint8_t i_o = i & 0x03;
            out[i_o] = ${config.relu_fn}(sum, out_mult, out_shift);
            if(i_o == 0x03)
            {
              out[0] = bitins(out[0], n_mask2, out[1], mask2, off2);
              out[0] = bitins(out[0], n_mask4, out[2], mask4, off4);
              *pOutBuffer = bitins(out[0], n_mask6, out[3], mask6, off6);
              pOutBuffer++;
            }
  %endif
          }
          else
          {
  %if config.kernel.out_data_t == 8:
            *pOutBuffer = (uint8_t) clip8(sum >> out_shift);
            pOutBuffer++;
  %elif config.kernel.out_data_t == 4:
            uint8_t i_o = i & 0x01;
            out[i_o] = (uint8_t) clip4(sum >> out_shift);
            if(i_o == 0x01)
            {
              *pOutBuffer = bitins(out[0], n_mask, out[1], mask, off);
              pOutBuffer++;
            }
  %elif config.kernel.out_data_t == 2:
            uint8_t i_o = i & 0x03;
            out[i_o] = (uint8_t) clip2(sum >> out_shift);
            if(i_o == 0x03)
            {
              out[0] = bitins(out[0], n_mask2, out[1], mask2, off2);
              out[0] = bitins(out[0], n_mask4, out[2], mask4, off4);
              *pOutBuffer = bitins(out[0], n_mask6, out[3], mask6, off6);
              pOutBuffer++;
            }
  %endif
          }
        }
  %elif config.kernel.out_data_t == 4:
        uint8_t i_o = i & 0x01;
        out[i_o] = pulp_nn_i4_quant(sum, pThr);
        pThr++;
        if(i_o == 0x01)
        {
          *pOutBuffer = bitins(out[0], n_mask, out[1], mask, off);
          pOutBuffer++;
        }
  %elif config.kernel.out_data_t == 2:
        uint8_t i_o = i & 0x03;
        out[i_o] = pulp_nn_i2_quant(sum, pThr);
        pThr++;
        if(i_o == 0x03)
        {
          out[0] = bitins(out[0], n_mask2, out[1], mask2, off2);
          out[0] = bitins(out[0], n_mask4, out[2], mask4, off4);
          *pOutBuffer = bitins(out[0], n_mask6, out[3], mask6, off6);
          pOutBuffer++;
        }
  %endif
      }
    }
    pOutBuffer+=(extra_chunk * ((dim_out_x_r + ((1 - section) * flag_dim_out_x_odd)) * ch_out_r));
    pIm2Col = pIm2ColBase;
  }
  pi_cl_team_barrier(0);
}