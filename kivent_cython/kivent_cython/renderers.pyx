from kivy.uix.widget import Widget
from kivy.properties import (StringProperty, ListProperty, NumericProperty, 
DictProperty, BooleanProperty, ObjectProperty)
from kivy.graphics import (PushMatrix, PopMatrix, Translate, Quad, Instruction, 
Rotate, Color, Scale, Point, Callback, RenderContext)
from kivy.core.image import Image as CoreImage
from kivy.atlas import Atlas
from kivy.clock import Clock
from kivy.graphics.transformation import Matrix
import json


class Renderer(GameSystem):
    system_id = StringProperty('renderer')
    updateable = BooleanProperty(True)
    renderable = BooleanProperty(True)
    do_rotate = BooleanProperty(False)
    do_color = BooleanProperty(False)
    do_scale = BooleanProperty(False)
    mesh = ObjectProperty(None, allownone=True)
    atlas_dir = StringProperty(None)
    atlas = StringProperty(None)
    shader_source = StringProperty('positionshader.glsl')

    def __init__(self, **kwargs):
        self.canvas = RenderContext(use_parent_projection=True)
        if 'shader_source' in kwargs:
            self.canvas.shader.source = kwargs.get('shader_source')
        super(Renderer, self).__init__(**kwargs)
        self.redraw = Clock.create_trigger(self.trigger_redraw)
        self.vertex_format = self.calculate_vertex_format()
        
    def on_shader_source(self, instance, value):
        self.canvas.shader.source = value

    def on_atlas(self, instance, value):
        if value and self.atlas_dir:
            self.uv_dict = self.return_uv_coordinates(
                value + '.atlas', value + '-0.png', self.atlas_dir)

    def on_atlas_dir(self, instance, value):
        if value and self.atlas:
            self.uv_dict = self.return_uv_coordinates(
                self.atlas + '.atlas', self.atlas + '-0.png', value)

    def on_do_rotate(self, instance, value):
        self.vertex_format = self.calculate_vertex_format()

    def on_do_scale(self, instance, value):
        self.vertex_format = self.calculate_vertex_format()

    def on_do_color(self, instance, value):
        self.vertex_format = self.calculate_vertex_format()

    def return_uv_coordinates(self, atlas_name, atlas_page, atlas_dir):
        uv_dict = {}
        uv_dict['main_texture'] = atlas = CoreImage(
            atlas_dir + atlas_page).texture
        size = atlas.size
        uv_dict['atlas_size'] = atlas_size = (float(size[0]), float(size[1]))
        w, h = atlas_size
        with open(atlas_dir + atlas_name, 'r') as fd:
            atlas_data = json.load(fd)
        atlas_content = atlas_data[atlas_page]
        for texture_name in atlas_content:
            data = atlas_content[texture_name]
            x1, y1 = data[0], data[1]
            x2, y2 = x1 + data[2], y1 + data[3]
            uv_dict[
                texture_name] = x1/w, 1.-y1/h, x2/w, 1.-y2/h, data[2], data[3]
        return uv_dict

    def calculate_vertex_format(self):
        vertex_format = [
            ('vPosition', 2, 'float'),
            ('vTexCoords0', 2, 'float'),
            ('vCenter', 2, 'float')
            ]
        if self.do_rotate:
            vertex_format.append(('vRotation', 1, 'float'))
        if self.do_color:
            vertex_format.append(('vColor', 4, 'float'))
        if self.do_scale:
            vertex_format.append(('vScale', 1, 'float'))
        self.clear_mesh()
        self.redraw()
        return vertex_format

    def trigger_redraw(self, dt):
        cdef list entity_ids = self.update_render_state()
        self.draw_mesh(entity_ids)

    def draw_mesh(self, list entities_to_draw):
        cdef object gameworld = self.gameworld
        cdef list entities = gameworld.entities
        cdef str system_id = self.system_id
        cdef list entity_ids = entities_to_draw
        do_color = self.do_color
        do_scale = self.do_scale
        do_rotate = self.do_rotate
        cdef str position_information_from
        cdef str scale_information_from
        cdef str rotate_information_from
        cdef str color_information_from
        cdef dict entity
        cdef dict system_data
        cdef dict position_information
        cdef dict scale_information
        cdef dict rotate_information
        cdef dict color_information
        vertex_format = self.vertex_format
        cdef list indices = []
        cdef dict uv_dict = self.uv_dict
        ie = indices.extend
        cdef list vertices = []
        e = vertices.extend
        for entity_n in range(len(entity_ids)):
            offset = 4 * entity_n
            ie([0 + offset, 1 + offset, 
                2 + offset, 2 + offset,
                3 + offset, 0 + offset])
        for entity_id in entity_ids:
            entity = entities[entity_id]
            if system_id not in entity:
                continue
            system_data = entity[system_id]
            position_from = system_data['position_from']
            if do_scale:
                scale_from = system_data['scale_from']
            if do_rotate:
                rotate_from = system_data['rotate_from']
            if do_color:
                color_from = system_data['color_from']
            if system_data['render']:
                tex_choice = system_data['texture']
                position = entity[position_from]['position']
                uv = uv_dict[tex_choice]
                w, h = uv[4], uv[5]
                x0, y0 = uv[0], uv[1]
                x1, y1 = uv[2], uv[3]
                vertex1 = [-w, -h, x0, y0, position[0], position[1]]
                vertex2 = [w, -h, x1, y0, position[0], position[1]]
                vertex3 = [w, h, x1, y1, position[0], position[1]]
                vertex4 = [-w, h, x0, y1, position[0], position[1]]
                verts = [vertex1, vertex2, vertex3, vertex4]
                if do_rotate:
                    rotate = entity[rotate_from]['angle']
                    for vert in verts:
                        vert.append(rotate)
                if do_color:
                    color = entity[color_from]['color']
                    for vert in verts:
                        vert.extend(color)
                if do_scale:
                    scale = entity[scale_from]['scale']
                    for vert in verts:
                        vert.append(scale)
                for vert in verts:
                    e(vert)
        if self.mesh == None:
            with self.canvas:
                self.mesh = Mesh(
                    indices=indices,
                    vertices=vertices,
                    fmt=vertex_format,
                    mode='triangles',
                    texture=uv_dict['main_texture'])
        else:
            self.mesh.vertices = vertices
            self.mesh.indices = indices

    def update(self, dt):
        cdef list entity_ids = self.update_render_state()
        self.draw_mesh(entity_ids)

    def update_render_state(self):
        cdef list entity_ids = self.entity_ids
        return entity_ids

    def clear_mesh(self):
        self.canvas.clear()
        self.mesh = None

    def remove_entity(self, int entity_id):
        super(Renderer, self).remove_entity(entity_id)
        self.redraw()

    def create_component(self, int entity_id, dict entity_component_dict):
        super(Renderer, self).create_component(
            entity_id, entity_component_dict)
        self.redraw()

    def generate_component_data(self, dict entity_component_dict):
        ''' You must provide at least a 'position_from', component 
        which contains a string referencing the entities 
        component that contains the 'position' attribute. 
        if do_rotate, do_color or do_scale is True you must also include,
        'rotate_from', 'color_from', and 'scale_from'.
        '''
        entity_component_dict['on_screen'] = False
        entity_component_dict['render'] = True
        return entity_component_dict

    def generate_entity_component_dict(self, int entity_id):
        entity = self.gameworld.entities[entity_id]
        entity_system_dict = entity[self.system_id]
        entity_component_dict = {'texture': entity_system_dict['texture']}
        return entity_component_dict


class DynamicRenderer(Renderer):
    system_id = StringProperty('dynamic_renderer')
    do_rotate = BooleanProperty(True)
    physics_system = StringProperty('cymunk-physics')

    def update_render_state(self):
        cdef object parent = self.gameworld
        cdef dict systems = parent.systems
        cdef list entities = parent.entities
        cdef str system_id = self.system_id
        cdef list entity_ids = self.entity_ids
        cdef object physics_system
        cdef list on_screen
        if self.physics_system in systems:
            physics_system = systems[self.physics_system]
            on_screen = physics_system.query_on_screen()
        else:
            on_screen = []
        cdef dict entity
        cdef dict system_data
        cdef list to_render = []
        for entity_id in entity_ids:
            entity = entities[entity_id]
            if system_id not in entity:
                continue
            system_data = entity[system_id]
            if not system_data['on_screen'] and entity_id in on_screen:
                system_data['on_screen'] = True
            if system_data['on_screen'] and not entity_id in on_screen:
                system_data['on_screen'] = False
            if entity_id in on_screen:
                to_render.append(entity_id)
            if system_data['on_screen'] and not system_data['render']:
                to_render.remove(entity_id)
        return to_render


class StaticQuadRenderer(Renderer):
    system_id = StringProperty('static_renderer')
    shader_source = StringProperty('positionshader.glsl')

    def update(self, dt):
        self.update_render_state()