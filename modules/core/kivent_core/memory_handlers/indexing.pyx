from block cimport MemoryBlock
from zone cimport MemoryZone
from pool cimport MemoryPool
from membuffer cimport Buffer

cdef class MemComponent:
    '''The base for a cdef extension that will work with the MemoryBlock 
    memory management system. Will store a pointer to the actual data, 
    and the index of the slot. All of the Python accessible components (and 
    the Entity class) inherit from this class.''' 

    def __cinit__(MemComponent self, MemoryBlock memory_block, 
        unsigned int index, unsigned int offset):
        self._id = index + offset
        self.pointer = memory_block.get_pointer(index)


cdef class BlockIndex:
    '''Ties a single MemoryBlock to a set of block_count MemComponent objects
    '''

    def __cinit__(BlockIndex self, MemoryBlock memory_block, 
        unsigned int offset, ComponentToCreate):
        cdef unsigned int count = memory_block.block_count
        self.block_objects = block_objects = []
        block_a = block_objects.append
        cdef unsigned int i
        for i in range(count):
            new_component = ComponentToCreate.__new__(ComponentToCreate, 
                memory_block, i, offset)
            block_a(new_component)

    property blocks:
        def __get__(BlockIndex self):
            return self.block_objects


cdef class PoolIndex:

    def __cinit__(PoolIndex self, MemoryPool memory_pool, ComponentToCreate, 
        start_offset):
        cdef unsigned int count = memory_pool.block_count
        cdef list blocks = memory_pool.memory_blocks
        self._block_indices = block_indices = []
        block_ind_a = block_indices.append
        cdef unsigned int i
        cdef unsigned int block_count
        cdef MemoryBlock block
        cdef unsigned int offset = start_offset
        for i in range(count):
            block = blocks[i]
            block_ind_a(BlockIndex(block, offset, ComponentToCreate))
            offset += block.block_count

    property block_indices:
        def __get__(PoolIndex self):
            return self._block_indices


cdef class ZoneIndex:

    def __cinit__(ZoneIndex self, MemoryZone memory_zone, ComponentToCreate):
        cdef unsigned int count = memory_zone.reserved_count
        cdef dict pool_indices = {}
        cdef dict memory_pools = memory_zone.memory_pools
        cdef unsigned int offset = 0
        cdef unsigned int pool_count
        cdef unsigned int i
        self.memory_zone = memory_zone
        cdef MemoryPool pool
        for i in range(count):
            pool = memory_pools[i]
            pool_count = pool.count
            pool_indices[i] = PoolIndex(pool, ComponentToCreate, offset)
            offset += pool_count
        self._pool_indices = pool_indices

    property pool_indices:
        def __get__(ZoneIndex self):
            return self._pool_indices

    def get_component_from_index(ZoneIndex self, unsigned int index):
        pool_i, block_i, slot_i = self.memory_zone.get_pool_block_slot_indices(
            index)
        cdef PoolIndex pool_index = self._pool_indices[pool_i]
        cdef BlockIndex block_index = pool_index._block_indices[block_i]
        return block_index.block_objects[slot_i]


cdef class IndexedMemoryZone:
    
    def __cinit__(IndexedMemoryZone self, Buffer master_buffer, 
        unsigned int block_size, unsigned int component_size, 
        dict reserved_spec, ComponentToCreate):
        cdef MemoryZone memory_zone = MemoryZone(block_size, 
            master_buffer, component_size, reserved_spec)
        cdef ZoneIndex zone_index = ZoneIndex(memory_zone, ComponentToCreate)
        self.zone_index = zone_index
        self.memory_zone = memory_zone

    def __getitem__(IndexedMemoryZone self, int index):
        return self.zone_index.get_component_from_index(index)

    cdef void* get_pointer(IndexedMemoryZone self, unsigned int index):
        return self.memory_zone.get_pointer(index)

    def __getslice__(IndexedMemoryZone self, int index_1, int index_2):
        cdef ZoneIndex zone_index = self.zone_index
        get_component_from_index = zone_index.get_component_from_index
        return [get_component_from_index(i) for i in range(index_1, index_2)]