"""Рендер превью рук (и предметов) из камеры вьюмодели в Blender."""
import math
import os

import bpy  # noqa: I001
import numpy as np


def setup_scene(res=(960, 540), fov4x3=62):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 24
    scn.cycles.device = "CPU"
    scn.render.resolution_x, scn.render.resolution_y = res
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.42, 0.5, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    scn.world = world
    cam_data = bpy.data.cameras.new("cam")
    aspect = res[0] / res[1]
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.angle = 2 * math.atan(math.tan(math.radians(fov4x3) / 2) * aspect / (4 / 3))
    cam_data.clip_start = 0.5
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(90), 0, math.radians(-90))  # смотрит вдоль +X, Z вверх
    scn.camera = cam
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(-30), math.radians(-60))
    bpy.context.collection.objects.link(so)
    return scn


def mesh_object(name, verts, tris_by_mat, colors):
    me = bpy.data.meshes.new(name)
    faces, mats = [], []
    for mi, tris in tris_by_mat.items():
        for t in tris:
            faces.append(t)
            mats.append(mi)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    for mi in sorted(set(mats)):
        m = bpy.data.materials.new(f"{name}_{mi}")
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = colors.get(mi, (0.6, 0.6, 0.6, 1))
        me.materials.append(m)
    lookup = {mi: k for k, mi in enumerate(sorted(set(mats)))}
    for p, mi in zip(me.polygons, mats):
        p.material_index = lookup[mi]
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def set_verts(ob, verts):
    ob.data.vertices.foreach_set("co", np.asarray(verts, np.float32).ravel())
    ob.data.update()


def render(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
