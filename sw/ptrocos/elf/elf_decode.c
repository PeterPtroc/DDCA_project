#include "elf_decode.h"
#include <string.h>
static uint32_t le16(const uint8_t *p) {return p[0]|((uint32_t)p[1]<<8);}
static uint32_t le32(const uint8_t *p) {return le16(p)|((uint32_t)le16(p+2)<<16);}
static int cancelled(const struct elf_source *s) {return s->cancelled && s->cancelled(s->context);}
static int read_at(const struct elf_source *s,uint32_t offset,void *data,unsigned size)
{
    if(cancelled(s)) return ELF_CANCEL;
    if(offset>s->size || size>s->size-offset) return ELF_FORMAT;
    return s->read(s->context,offset,data,size);
}
static int note(const struct elf_source *s,uint32_t offset,uint32_t bytes,unsigned *found)
{
    if((uint64_t)offset+bytes>s->size || bytes>4096) return ELF_FORMAT;
    uint32_t end=offset+bytes;
    while(offset<end) {
        uint8_t header[12],name[8],descriptor[16];
        if(end-offset<12) return ELF_FORMAT;
        int result=read_at(s,offset,header,12);if(result) return result;
        uint32_t names=le32(header),desc=le32(header+4),type=le32(header+8);
        uint64_t padded_name=((uint64_t)names+3)&~UINT64_C(3);
        uint64_t padded_desc=((uint64_t)desc+3)&~UINT64_C(3);
        uint64_t next=(uint64_t)offset+12+padded_name+padded_desc;
        if(next>end) return ELF_FORMAT;
        if(names==8) {
            result=read_at(s,offset+12,name,8);if(result) return result;
            if(!memcmp(name,"PtrocOS",8)) {
                if(*found || type!=1 || desc!=16) return ELF_ABI;
                result=read_at(s,offset+20,descriptor,16);if(result) return result;
                if(le32(descriptor)!=1 || le32(descriptor+4)!=4096 ||
                   le32(descriptor+8)!=PTROCOS_APP_CODE_BASE || le32(descriptor+12)!=PTROCOS_APP_DATA_BASE)
                    return ELF_ABI;
                *found=1;
            }
        }
        offset=(uint32_t)next;
    }
    return ELF_OK;
}
int ptrocos_elf_inspect(const struct elf_source *s,struct elf_image *image)
{
    if(!image) return ELF_FORMAT;
    memset(image,0,sizeof(*image));
    if(!s || !s->read) return ELF_FORMAT;
    uint8_t header[52];int result=read_at(s,0,header,sizeof(header));if(result) return result;
    if(memcmp(header,"\177ELF",4) || header[4]!=1 || header[5]!=1 || header[6]!=1 ||
       header[7]!=0 || header[8]!=0 || le16(header+16)!=2 || le16(header+18)!=243 ||
       le32(header+20)!=1 || le16(header+40)!=52 || le16(header+42)!=32) return ELF_FORMAT;
    // This platform supports soft-float ILP32 with 32-bit instruction alignment.
    // e_flags alone does not certify the ISA of every instruction.
    if(le32(header+36)) return ELF_ABI;
    uint32_t table=le32(header+28),count=le16(header+44);
    if(!count || count>PTROCOS_ELF_SEGMENTS || table<52 || (uint64_t)table+count*32>s->size)
        return ELF_FORMAT;
    image->entry=le32(header+24);
    if(image->entry&3U) return ELF_RANGE;
    unsigned abi=0,entry_found=0;
    for(uint32_t i=0;i<count;i++) {
        uint8_t row[32];result=read_at(s,table+i*32,row,32);if(result) return result;
        uint32_t type=le32(row),offset=le32(row+4),address=le32(row+8),physical=le32(row+12);
        uint32_t files=le32(row+16),memory=le32(row+20),flags=le32(row+24),align=le32(row+28);
        if(type==0) continue;
        if(type==4) {result=note(s,offset,files,&abi);if(result) return result;continue;}
        if(type==0x6474e551U) {if(flags&1U) return ELF_ABI;continue;}
        if(type==6 || type==0x70000003U) {
            if((uint64_t)offset+files>s->size) return ELF_FORMAT;
            continue;
        }
        if(type!=1) return ELF_ABI;
        if(files>memory || (uint64_t)offset+files>s->size ||
           (align>1 && ((align&(align-1)) || ((address^offset)&(align-1))))) return ELF_FORMAT;
        if(physical && physical!=address) return ELF_RANGE;
        if((flags&~7U) || !(flags&4U) || (flags&3U)==3U) return ELF_ABI;
        uint64_t end=(uint64_t)address+memory;
        if(!memory) return ELF_RANGE;
        if(address>=PTROCOS_APP_CODE_BASE && end<=PTROCOS_APP_CODE_END) {
            if(flags&2U) return ELF_ABI;
        } else if(address>=PTROCOS_APP_DATA_BASE && end<=PTROCOS_APP_DATA_END) {
            if(flags&1U) return ELF_ABI;
        } else return ELF_RANGE;
        if(image->count) {
            const struct elf_segment *previous=&image->segments[image->count-1];
            if(address<(uint64_t)previous->address+previous->memory_bytes) return ELF_RANGE;
        }
        struct elf_segment *segment=&image->segments[image->count++];
        *segment=(struct elf_segment){offset,address,files,memory,flags};
        image->file_bytes+=files;image->memory_bytes+=memory;
        if((flags&1U) && image->entry>=address && (uint64_t)image->entry+4<=(uint64_t)address+files)
            entry_found=1;
    }
    if(!abi) return ELF_ABI;
    if(!image->count || !entry_found) return ELF_RANGE;
    image->abi_version=1;return ELF_OK;
}
int ptrocos_elf_load(const struct elf_source *source,const struct elf_sink *sink,struct elf_image *image)
{
    int result=ptrocos_elf_inspect(source,image);if(result) return result;
    if(!sink || !sink->write) return ELF_OUTPUT;
    uint8_t buffer[256];
    for(uint32_t i=0;i<image->count;i++) {
        const struct elf_segment *segment=&image->segments[i];
        for(uint32_t position=0;position<segment->memory_bytes;) {
            if(cancelled(source)) return ELF_CANCEL;
            unsigned count=segment->memory_bytes-position;
            if(count>sizeof(buffer)) count=sizeof(buffer);
            if(position<segment->file_bytes) {
                if(count>segment->file_bytes-position) count=segment->file_bytes-position;
                result=read_at(source,segment->offset+position,buffer,count);if(result) return result;
            } else memset(buffer,0,count);
            result=sink->write(sink->context,segment->address+position,buffer,count);
            if(result) return result;
            position+=count;if(sink->progress) sink->progress(sink->context);
        }
    }
    if(cancelled(source)) return ELF_CANCEL;
    image->loaded=1;return ELF_OK;
}
