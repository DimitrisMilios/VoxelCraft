shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

#define CUTOUT
#include "res://shaders/voxel_terrain.gdshaderinc"
