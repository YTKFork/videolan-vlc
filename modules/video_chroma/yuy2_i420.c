/*****************************************************************************
 * yuy2_i420.c : Packed YUV 4:2:2 to Planar YUV conversion module for vlc
 *****************************************************************************
 * Copyright (C) 2007 VLC authors and VideoLAN
 *
 * Authors: Antoine Cellerier <dionoea at videolan dot org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>
#include <vlc_picture.h>
#include <vlc_chroma_probe.h>

#define SRC_FOURCC "YUY2,YUNV,YVYU,UYVY,UYNV,Y422"
#define DEST_FOURCC  "I420"

/*****************************************************************************
 * Local and extern prototypes.
 *****************************************************************************/
static int  Activate ( filter_t * );

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/

static void ProbeChroma(vlc_chroma_conv_vec *vec)
{
    vlc_chroma_conv_add(vec, 1, VLC_CODEC_YUYV, VLC_CODEC_I420, false);
    vlc_chroma_conv_add(vec, 1, VLC_CODEC_YVYU, VLC_CODEC_I420, false);
    vlc_chroma_conv_add(vec, 1, VLC_CODEC_UYVY, VLC_CODEC_I420, false);
}

vlc_module_begin ()
    set_description( N_("Conversions from " SRC_FOURCC " to " DEST_FOURCC) )
    set_callback_video_converter( Activate, 80 )
    add_submodule()
        set_callback_chroma_conv_probe(ProbeChroma)
vlc_module_end ()

VIDEO_FILTER_WRAPPER( YUY2_I420 )
VIDEO_FILTER_WRAPPER( YVYU_I420 )
VIDEO_FILTER_WRAPPER( UYVY_I420 )

/*****************************************************************************
 * Activate: allocate a chroma function
 *****************************************************************************
 * This function allocates and initializes a chroma function
 *****************************************************************************/
static int Activate( filter_t *p_filter )
{
    if( p_filter->fmt_in.video.i_width & 1
     || p_filter->fmt_in.video.i_height & 1 )
    {
        return -1;
    }

    if( p_filter->fmt_in.video.i_width != (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width)
     || p_filter->fmt_in.video.i_height != (p_filter->fmt_out.video.i_y_offset + p_filter->fmt_out.video.i_visible_height)
     || p_filter->fmt_in.video.orientation != p_filter->fmt_out.video.orientation)
        return -1;

    switch( p_filter->fmt_out.video.i_chroma )
    {
        case VLC_CODEC_I420:
            switch( p_filter->fmt_in.video.i_chroma )
            {
                case VLC_CODEC_YUYV:
                    p_filter->ops = &YUY2_I420_ops;
                    break;

                case VLC_CODEC_YVYU:
                    p_filter->ops = &YVYU_I420_ops;
                    break;

                case VLC_CODEC_UYVY:
                    p_filter->ops = &UYVY_I420_ops;
                    break;

                default:
                    return -1;
            }
            break;

        default:
            return -1;
    }
    return 0;
}

/* Following functions are local */

/*****************************************************************************
 * YUY2_I420: packed YUY2 4:2:2 to planar YUV 4:2:0
 *****************************************************************************/
static void YUY2_I420( filter_t *p_filter, picture_t *p_source,
                                           picture_t *p_dest )
{
    uint8_t *p_line = p_source->p->p_pixels;

    uint8_t *p_y = p_dest->Y_PIXELS;
    uint8_t *p_u = p_dest->U_PIXELS;
    uint8_t *p_v = p_dest->V_PIXELS;

    int i_x, i_y;

    const int i_dest_margin = p_dest->p[0].i_pitch
                                 - p_dest->p[0].i_visible_pitch
                                 - p_filter->fmt_out.video.i_x_offset;
    const int i_dest_margin_c = p_dest->p[1].i_pitch
                                 - p_dest->p[1].i_visible_pitch
                                 - ( p_filter->fmt_out.video.i_x_offset / 2 );
    const int i_source_margin = p_source->p->i_pitch
                               - p_source->p->i_visible_pitch
                               - ( p_filter->fmt_in.video.i_x_offset * 2 );

    bool b_skip = false;

    for( i_y = (p_filter->fmt_out.video.i_y_offset + p_filter->fmt_out.video.i_visible_height) ; i_y-- ; )
    {
        if( b_skip )
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v )      \
                *p_y++ = *p_line++; p_line++; \
                *p_y++ = *p_line++; p_line++
                C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_YUYV_YUV422_skip( p_line, p_y, p_u, p_v );
            }
        }
        else
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_YUYV_YUV422( p_line, p_y, p_u, p_v )      \
                *p_y++ = *p_line++; *p_u++ = *p_line++; \
                *p_y++ = *p_line++; *p_v++ = *p_line++
                C_YUYV_YUV422( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422( p_line, p_y, p_u, p_v );
                C_YUYV_YUV422( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_YUYV_YUV422( p_line, p_y, p_u, p_v );
            }
            p_u += i_dest_margin_c;
            p_v += i_dest_margin_c;
        }
        p_line += i_source_margin;
        p_y += i_dest_margin;

        b_skip = !b_skip;
    }
}

/*****************************************************************************
 * YVYU_I420: packed YVYU 4:2:2 to planar YUV 4:2:0
 *****************************************************************************/
static void YVYU_I420( filter_t *p_filter, picture_t *p_source,
                                           picture_t *p_dest )
{
    uint8_t *p_line = p_source->p->p_pixels;

    uint8_t *p_y = p_dest->Y_PIXELS;
    uint8_t *p_u = p_dest->U_PIXELS;
    uint8_t *p_v = p_dest->V_PIXELS;

    int i_x, i_y;

    const int i_dest_margin = p_dest->p[0].i_pitch
                                 - p_dest->p[0].i_visible_pitch
                                 - p_filter->fmt_out.video.i_x_offset;
    const int i_dest_margin_c = p_dest->p[1].i_pitch
                                 - p_dest->p[1].i_visible_pitch
                                 - ( p_filter->fmt_out.video.i_x_offset / 2 );
    const int i_source_margin = p_source->p->i_pitch
                               - p_source->p->i_visible_pitch
                               - ( p_filter->fmt_in.video.i_x_offset * 2 );

    bool b_skip = false;

    for( i_y = (p_filter->fmt_out.video.i_y_offset + p_filter->fmt_out.video.i_visible_height) ; i_y-- ; )
    {
        if( b_skip )
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v )      \
                *p_y++ = *p_line++; p_line++; \
                *p_y++ = *p_line++; p_line++
                C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_YVYU_YUV422_skip( p_line, p_y, p_u, p_v );
            }
        }
        else
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_YVYU_YUV422( p_line, p_y, p_u, p_v )      \
                *p_y++ = *p_line++; *p_v++ = *p_line++; \
                *p_y++ = *p_line++; *p_u++ = *p_line++
                C_YVYU_YUV422( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422( p_line, p_y, p_u, p_v );
                C_YVYU_YUV422( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_YVYU_YUV422( p_line, p_y, p_u, p_v );
            }
            p_u += i_dest_margin_c;
            p_v += i_dest_margin_c;
        }
        p_line += i_source_margin;
        p_y += i_dest_margin;

        b_skip = !b_skip;
    }
}

/*****************************************************************************
 * UYVY_I420: packed UYVY 4:2:2 to planar YUV 4:2:0
 *****************************************************************************/
static void UYVY_I420( filter_t *p_filter, picture_t *p_source,
                                           picture_t *p_dest )
{
    uint8_t *p_line = p_source->p->p_pixels;

    uint8_t *p_y = p_dest->Y_PIXELS;
    uint8_t *p_u = p_dest->U_PIXELS;
    uint8_t *p_v = p_dest->V_PIXELS;

    int i_x, i_y;

    const int i_dest_margin = p_dest->p[0].i_pitch
                                 - p_dest->p[0].i_visible_pitch
                                 - p_filter->fmt_out.video.i_x_offset;
    const int i_dest_margin_c = p_dest->p[1].i_pitch
                                 - p_dest->p[1].i_visible_pitch
                                 - ( p_filter->fmt_out.video.i_x_offset / 2 );
    const int i_source_margin = p_source->p->i_pitch
                               - p_source->p->i_visible_pitch
                               - ( p_filter->fmt_in.video.i_x_offset * 2 );

    bool b_skip = false;

    for( i_y = (p_filter->fmt_out.video.i_y_offset + p_filter->fmt_out.video.i_visible_height) ; i_y-- ; )
    {
        if( b_skip )
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v )      \
                *p_u++ = *p_line++; p_line++; \
                *p_v++ = *p_line++; p_line++
                C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_UYVY_YUV422_skip( p_line, p_y, p_u, p_v );
            }
        }
        else
        {
            for( i_x = (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) / 8 ; i_x-- ; )
            {
    #define C_UYVY_YUV422( p_line, p_y, p_u, p_v )      \
                *p_u++ = *p_line++; *p_y++ = *p_line++; \
                *p_v++ = *p_line++; *p_y++ = *p_line++
                C_UYVY_YUV422( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422( p_line, p_y, p_u, p_v );
                C_UYVY_YUV422( p_line, p_y, p_u, p_v );
            }
            for( i_x = ( (p_filter->fmt_out.video.i_x_offset + p_filter->fmt_out.video.i_visible_width) % 8 ) / 2; i_x-- ; )
            {
                C_UYVY_YUV422( p_line, p_y, p_u, p_v );
            }
            p_y += i_dest_margin;
        }
        p_line += i_source_margin;
        p_u += i_dest_margin_c;
        p_v += i_dest_margin_c;

        b_skip = !b_skip;
    }
}
