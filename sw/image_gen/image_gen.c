// #################################################################################################
// # << CELLRV32 - Executable image generator tool >>                                              #
// # ********************************************************************************************* #
// # The CELLRV32 Processor - https://github.com/datNguyen97-VN/cellrv32            (c) Dat Nguyen #
// #################################################################################################

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>


const uint32_t signature = 0x4788CAFE;

int main(int argc, char *argv[]) {

  if ((argc != 4) && (argc != 5)){
    printf("<<< CELLRV32 executable image generator >>>\n"
           "by Stephan Nolting\n"
           "Three arguments are required.\n"
           "1st: Option\n"
           " -app_bin : Generate application executable binary (binary file, little-endian, with header) \n"
           " -app_img : Generate application raw executable memory image (vhdl package body file, no header)\n"
           " -raw_hex : Generate application raw executable (ASCII hex file, no header)\n"
           " -raw_bin : Generate application raw executable (binary file, no header)\n"
           " -bld_img : Generate bootloader raw executable memory image (vhdl package body file, no header)\n"
           "2nd: Input file (raw binary image)\n"
           "3rd: Output file\n"
           "4th: Project folder (optional)\n");
    return 0;
  }

  FILE *input, *output;
  unsigned char buffer[4];
  char tmp_string[1024];
  uint32_t tmp = 0, size = 0, checksum = 0;
  unsigned int i = 0;
  int option = 0;
  unsigned long raw_exe_size = 0;

  if (strcmp(argv[1], "-app_bin") == 0)
    option = 1;
  else if (strcmp(argv[1], "-app_img") == 0)
    option = 2;
  else if (strcmp(argv[1], "-bld_img") == 0)
    option = 3;
  else if (strcmp(argv[1], "-raw_hex") == 0)
    option = 4;
  else if (strcmp(argv[1], "-raw_bin") == 0)
    option = 5;
  else {
    printf("Invalid option!");
    return 1;
  }

  // open input file
  input = fopen(argv[2], "rb");
  if(input == NULL){
    printf("Input file error!");
    return 2;
  }

  // open output file
  output = fopen(argv[3], "wb");
  if(output == NULL){
    printf("Output file error!");
    return 3;
  }

  // get input file size
  fseek(input, 0L, SEEK_END);
  unsigned int input_size = (unsigned int)ftell(input);
  rewind(input);
  unsigned int input_words = input_size / 4;


// ------------------------------------------------------------
// Try to find out targeted CPU configuration
// via MARCH environment variable
// ------------------------------------------------------------
  char string_march[64] = "default";
  char *envvar_march = "MARCH";
  if (getenv(envvar_march)) {
    if (snprintf(string_march, 64, "%s", getenv(envvar_march)) >= 64){
      strcpy(string_march, "default");
    }
  }


// ------------------------------------------------------------
// Get image's compilation date and time
// ------------------------------------------------------------
  time_t time_current;
  time(&time_current);
  struct tm *time_local = localtime(&time_current);
  char compile_time[64];

  snprintf(compile_time, 64, "%02d.%02d.%d %02d:%02d:%02d",
    time_local->tm_mday,
    time_local->tm_mon + 1,
    time_local->tm_year + 1900,
    time_local->tm_hour,
    time_local->tm_min,
    time_local->tm_sec
  );


// ------------------------------------------------------------
// Get size of application (in bytes)
// ------------------------------------------------------------
  fseek(input, 0L, SEEK_END);

  // get file size (raw executable)
  raw_exe_size = (unsigned long)ftell(input);

  // go back to beginning
  rewind(input);


// ------------------------------------------------------------
// Generate BINARY executable (with header!) for bootloader upload
// ------------------------------------------------------------
  if (option == 1) {

    // reserve header space for signature
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);

    // reserve header space for size
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);

    // reserve header space for checksum
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);
    fputc(0, output);

    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 0;

    checksum = 0;
    size = 0;
    rewind(input);
    while(fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
      tmp  = (uint32_t)(buffer[0] << 0);
      tmp |= (uint32_t)(buffer[1] << 8);
      tmp |= (uint32_t)(buffer[2] << 16);
      tmp |= (uint32_t)(buffer[3] << 24);
      checksum += tmp; // checksum: sum complement
      fputc(buffer[0], output);
      fputc(buffer[1], output);
      fputc(buffer[2], output);
      fputc(buffer[3], output);
      size += 4;
    }

    rewind(output);
    // header: signature
    fputc((unsigned char)((signature >>  0) & 0xFF), output);
    fputc((unsigned char)((signature >>  8) & 0xFF), output);
    fputc((unsigned char)((signature >> 16) & 0xFF), output);
    fputc((unsigned char)((signature >> 24) & 0xFF), output);
    // header: size
    fputc((unsigned char)((size >>  0) & 0xFF), output);
    fputc((unsigned char)((size >>  8) & 0xFF), output);
    fputc((unsigned char)((size >> 16) & 0xFF), output);
    fputc((unsigned char)((size >> 24) & 0xFF), output);
    // header: checksum (sum complement)
    checksum = (~checksum) + 1;
    fputc((unsigned char)((checksum >>  0) & 0xFF), output);
    fputc((unsigned char)((checksum >>  8) & 0xFF), output);
    fputc((unsigned char)((checksum >> 16) & 0xFF), output);
    fputc((unsigned char)((checksum >> 24) & 0xFF), output);
  }


// ------------------------------------------------------------
// Generate APPLICATION's executable memory initialization file (no header!)
// => VHDL package body
// ------------------------------------------------------------
  if (option == 2) {

    // header
    sprintf(tmp_string, "-- The CELLRV32 RISC-V Processor: https://github.com/DatNguyen97-VN/cellrv32\n"
                        "-- Auto-generated memory initialization file (for APPLICATION) from source file <%s/%s>\n"
                        "-- Size: %lu bytes\n"
                        "-- MARCH: %s\n"
                        "-- Built: %s\n"
                        "\n"
                        "-- prototype defined in 'neorv32_package.vhd'\n"
                        "package body cellrv32_application_image is\n"
                        "\n"
                        "constant application_init_image : mem32_t := (\n", argv[4], argv[2], raw_exe_size, string_march, compile_time);
    fputs(tmp_string, output);

    // data
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 0;
    i = 0;

    while (i < (input_words-1)) {
      if (fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
        tmp  = (uint32_t)(buffer[0] << 0);
        tmp |= (uint32_t)(buffer[1] << 8);
        tmp |= (uint32_t)(buffer[2] << 16);
        tmp |= (uint32_t)(buffer[3] << 24);
        sprintf(tmp_string, "x\"%08x\",\n", (unsigned int)tmp);
        fputs(tmp_string, output);
        buffer[0] = 0;
        buffer[1] = 0;
        buffer[2] = 0;
        buffer[3] = 0;
        i++;
      }
      else {
        printf("Unexpected input file end!\n");
        break;
      }
    }

    if (fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
      tmp  = (uint32_t)(buffer[0] << 0);
      tmp |= (uint32_t)(buffer[1] << 8);
      tmp |= (uint32_t)(buffer[2] << 16);
      tmp |= (uint32_t)(buffer[3] << 24);
      sprintf(tmp_string, "x\"%08x\"\n", (unsigned int)tmp);
      fputs(tmp_string, output);
      buffer[0] = 0;
      buffer[1] = 0;
      buffer[2] = 0;
      buffer[3] = 0;
      i++;
    }
    else {
      printf("Unexpected input file end!\n");
    }

    // end
    sprintf(tmp_string, ");\n"
                        "\n"
                        "end cellrv32_application_image;\n");
    fputs(tmp_string, output);
  }


// ------------------------------------------------------------
// Generate BOOTLOADER's executable memory initialization file (no header!)
// => VHDL package body
// ------------------------------------------------------------
  if (option == 3) {

    // header
    sprintf(tmp_string, "-- The CELLRV32 RISC-V Processor: https://github.com/DatNguyen97-VN/cellrv32\n"
                        "-- Auto-generated memory initialization file (for BOOTLOADER) from source file <%s/%s>\n"
                        "-- Size: %lu bytes\n"
                        "-- MARCH: %s\n"
                        "-- Built: %s\n"
                        "\n"
                        "-- prototype defined in 'neorv32_package.vhd'\n"
                        "package body cellrv32_bootloader_image is\n"
                        "\n"
                        "constant bootloader_init_image : mem32_t := (\n", argv[4], argv[2], raw_exe_size, string_march, compile_time);
    fputs(tmp_string, output);

    // data
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 0;
    i = 0;

    while (i < (input_words-1)) {
      if (fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
        tmp  = (uint32_t)(buffer[0] << 0);
        tmp |= (uint32_t)(buffer[1] << 8);
        tmp |= (uint32_t)(buffer[2] << 16);
        tmp |= (uint32_t)(buffer[3] << 24);
        sprintf(tmp_string, "x\"%08x\",\n", (unsigned int)tmp);
        fputs(tmp_string, output);
        buffer[0] = 0;
        buffer[1] = 0;
        buffer[2] = 0;
        buffer[3] = 0;
        i++;
      }
      else {
        printf("Unexpected input file end!\n");
        break;
      }
    }

    if (fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
      tmp  = (uint32_t)(buffer[0] << 0);
      tmp |= (uint32_t)(buffer[1] << 8);
      tmp |= (uint32_t)(buffer[2] << 16);
      tmp |= (uint32_t)(buffer[3] << 24);
      sprintf(tmp_string, "x\"%08x\"\n", (unsigned int)tmp);
      fputs(tmp_string, output);
      buffer[0] = 0;
      buffer[1] = 0;
      buffer[2] = 0;
      buffer[3] = 0;
      i++;
    }
    else {
      printf("Unexpected input file end!\n");
    }

    // end
    sprintf(tmp_string, ");\n"
                        "\n"
                        "end cellrv32_bootloader_image;\n");
    fputs(tmp_string, output);
  }


// ------------------------------------------------------------
// Generate raw APPLICATION's executable ASCII hex file (no header!!!)
// ------------------------------------------------------------
  if (option == 4) {

    // data
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 0;

    while(fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
      tmp  = (uint32_t)(buffer[0] << 0);
      tmp |= (uint32_t)(buffer[1] << 8);
      tmp |= (uint32_t)(buffer[2] << 16);
      tmp |= (uint32_t)(buffer[3] << 24);
      sprintf(tmp_string, "%08x\n", (unsigned int)tmp);
      fputs(tmp_string, output);
    }
  }


// ------------------------------------------------------------
// Generate raw APPLICATION's executable binary file (no header!!!)
// ------------------------------------------------------------
  if (option == 5) {

    // data
    buffer[0] = 0;
    buffer[1] = 0;
    buffer[2] = 0;
    buffer[3] = 0;

    while(fread(&buffer, sizeof(unsigned char), 4, input) != 0) {
      tmp  = (uint32_t)(buffer[0] << 0);
      tmp |= (uint32_t)(buffer[1] << 8);
      tmp |= (uint32_t)(buffer[2] << 16);
      tmp |= (uint32_t)(buffer[3] << 24);
      fputc(buffer[0], output);
      fputc(buffer[1], output);
      fputc(buffer[2], output);
      fputc(buffer[3], output);
    }
  }


// ------------------------------------------------------------
// Done, clean up
// ------------------------------------------------------------

  fclose(input);
  fclose(output);

  return 0;
}
