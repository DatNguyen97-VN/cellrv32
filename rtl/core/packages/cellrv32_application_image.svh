// The CELLRV32 RISC-V Processor: https://github.com/DatNguyen97-VN/cellrv32
// Auto-generated memory initialization file (for APPLICATION) from source file <bootloader/main.bin>
// Size: 2960 bytes (1 cell = 4 byte)
// MARCH: default
// Built: 21.09.2024 19:02:24


// Memory with 32-bit entries, 32kb = 8192 cell, 1 cell = 4(B)
typedef logic [31:0] mem_app_t   [32*1024];
typedef logic [31:0] mem32_app_t [740];
// Function: Initialize mem32_t array from another mem32_t array -----------------------------
// -------------------------------------------------------------------------------------------
// impure function: returns NOT the same result every time it is evaluated with the same arguments since the source file might have changed
function mem_app_t mem32_init_app_f(input mem32_app_t init, input integer depth);
  mem_app_t mem_v;
  // make sure remaining memory entries are set to zero
  mem_v = '{default: '0};
  //
  if ($size(init) > depth) begin
     return mem_v;
  end
  // init only in range of source data array
  for (int idx_v = 0; idx_v < $size(init); ++idx_v) begin
    mem_v[idx_v] = init[idx_v];
  end
  return mem_v;
endfunction : mem32_init_app_f

const logic [31:0] application_init_image [740] = '{
32'h30005073,
32'h30401073,
32'h00000097,
32'h0a008093,
32'h30509073,
32'h80010117,
32'h1e810113,
32'h80010197,
32'h7e418193,
32'h42814201,
32'h43814301,
32'h44814401,
32'h48814801,
32'h49814901,
32'h4a814a01,
32'h4b814b01,
32'h4c814c01,
32'h4d814d01,
32'h4e814e01,
32'h4f814f01,
32'h00001597,
32'hb4058593,
32'h80010617,
32'hfa860613,
32'h80010697,
32'hfa068693,
32'h00c58963,
32'h00d65763,
32'hc2184198,
32'h06110591,
32'h0717bfd5,
32'h07138001,
32'h8793f867,
32'h56638081,
32'h202300f7,
32'h07110007,
32'h4501bfdd,
32'h00ef4581,
32'h107304a0,
32'h10733040,
32'h00733405,
32'ha0011050,
32'hc0221161,
32'h2473c226,
32'h42633420,
32'h24730204,
32'h14833410,
32'h888d0004,
32'h10730409,
32'h440d3414,
32'h00941763,
32'h34102473,
32'h10730409,
32'h44023414,
32'h01214492,
32'h30200073,
32'hc2a6715d,
32'h800004b7,
32'h0004a223,
32'h800007b7,
32'h0007a023,
32'hffff07b7,
32'hc4a2c686,
32'hde4ec0ca,
32'hda56dc52,
32'hd65ed85a,
32'hd266d462,
32'hce6ed06a,
32'h70c78793,
32'h30579073,
32'hfe802783,
32'h00080737,
32'hc7998ff9,
32'hfa002423,
32'h10100793,
32'hfaf02423,
32'hfe802783,
32'h40000737,
32'hcfa98ff9,
32'hf4002023,
32'hf4002423,
32'h26236799,
32'h8793f400,
32'h20232057,
32'h2423f4f0,
32'h2623f400,
32'h06b7f400,
32'h07934000,
32'h4398f400,
32'hff658f75,
32'h06b74398,
32'h8f550200,
32'h4398c398,
32'h080006b7,
32'hc3988f55,
32'he6b74398,
32'h8693fe1f,
32'h8f7543f6,
32'h008016b7,
32'h60068693,
32'hc3988f55,
32'hfe802783,
32'h8ff96741,
32'h4785c791,
32'hfcf02423,
32'hfc002623,
32'hfa002023,
32'hfe002603,
32'h05936725,
32'h47816007,
32'h5ff70713,
32'h02b786b3,
32'h40d606b3,
32'h18d76363,
32'h06134701,
32'h60633fe0,
32'h17fd18f6,
32'h16fd66c1,
32'h070e079a,
32'h8b618ff5,
32'he7938fd9,
32'h20230037,
32'h5701faf0,
32'h06b7471c,
32'h8ff50002,
32'h2823c395,
32'h2a23f800,
32'h431cf800,
32'h2c238389,
32'h2e23f8f0,
32'h0793f800,
32'h90730800,
32'h47a13047,
32'h3007a073,
32'hffff1537,
32'h98850513,
32'h257329b5,
32'h213df130,
32'hffff1537,
32'h9c050513,
32'h540121b5,
32'h29394048,
32'hffff1537,
32'h9c850513,
32'h400829b1,
32'h15372901,
32'h0513ffff,
32'h21b99d05,
32'h30102573,
32'h15372101,
32'h0513ffff,
32'h293d9d85,
32'hfc002573,
32'h15372ec5,
32'h0513ffff,
32'h213d9e05,
32'h19374408,
32'h2ef9ffff,
32'hffff1537,
32'h9e850513,
32'h4c082931,
32'h05132ec1,
32'h29099f09,
32'h26d94808,
32'hffff1537,
32'h9fc50513,
32'h4c482111,
32'h05132e65,
32'h2eed9f09,
32'h19374848,
32'h266dffff,
32'h98490513,
32'h441c26f5,
32'h00020737,
32'hc3b18ff9,
32'hffff1537,
32'ha0450513,
32'h24212ee1,
32'h0a374000,
32'h6ac10004,
32'h09b3040e,
32'hb43300a4,
32'h942e0089,
32'hfe802783,
32'h0147f7b3,
32'h0713cfb5,
32'h431cfa00,
32'h0157f7b3,
32'h1537cba5,
32'h435cffff,
32'ha3050513,
32'h1a372645,
32'h0513ffff,
32'h2e59a3ca,
32'h06c00a93,
32'h07800b93,
32'h07300c13,
32'h06500c93,
32'hffff17b7,
32'habc78513,
32'h07132eb5,
32'h431cfa00,
32'h8ff566c1,
32'h4340dbfd,
32'h0ff47413,
32'h26318522,
32'h98490513,
32'h07932685,
32'h1d630720,
32'h72c102f4,
32'h07858282,
32'h0693bd85,
32'h9af5ffe7,
32'h838de681,
32'hbd950705,
32'hbfed8385,
32'hede322bd,
32'h1463f685,
32'h69e300b4,
32'h4505f735,
32'h05132949,
32'h261d9849,
32'h2b854501,
32'h13540763,
32'h028ae363,
32'h13940563,
32'h06800793,
32'ha3ca0513,
32'h02f40a63,
32'h03f00793,
32'h12f40663,
32'hffff1537,
32'hb6050513,
32'h0793a005,
32'h0f630750,
32'h096300f4,
32'h15e31174,
32'ha403ff84,
32'he8110044,
32'hffff1537,
32'hac450513,
32'hbf892ce1,
32'h29254501,
32'h1537b7b1,
32'h0513ffff,
32'h24d9ae05,
32'h2cad8522,
32'hffff1537,
32'hae850513,
32'h05372c65,
32'h24ad0040,
32'hffff1537,
32'hb0050513,
32'h66c12465,
32'hfa000713,
32'h8ff5431c,
32'h2983dfe5,
32'hf9930047,
32'h854e0ff9,
32'h07932c1d,
32'h93e30790,
32'h2a65f0f9,
32'h450dc119,
32'h15372c45,
32'h0513ffff,
32'h2c9db0c5,
32'h01045b13,
32'h004009b7,
32'h5d7d6dc1,
32'h28cd2a85,
32'h0d800513,
32'h854e2845,
32'h287120c9,
32'h89052a85,
32'h1b7dfd75,
32'h13e399ee,
32'h2683ffab,
32'h09b7ff00,
32'h4d010040,
32'h87934d81,
32'h073300c9,
32'h430c00dd,
32'h00fd0533,
32'h9daec636,
32'h07b72249,
32'h0d110040,
32'h07b146b2,
32'hfe8d63e3,
32'h4788d5b7,
32'hafe58593,
32'h00400537,
32'h85a2229d,
32'h00498513,
32'h85132ab9,
32'h05b30089,
32'h2a9141b0,
32'hffff1537,
32'h96c50513,
32'h4505bf31,
32'ha783bf39,
32'h93e30044,
32'h1537ec07,
32'h0513ffff,
32'hb719b1c5,
32'hbd654505,
32'hffff1537,
32'hb2c50513,
32'h0793bde5,
32'h43ccf900,
32'h43dc4388,
32'hfef59be3,
32'h07138082,
32'h431cfa80,
32'hfbf7f793,
32'h8082c31c,
32'hfaa02623,
32'hfa800793,
32'h4de34398,
32'h43c8fe07,
32'h0ff57513,
32'h11418082,
32'h842ac422,
32'h75138141,
32'hc6060ff5,
32'h55133ff1,
32'h75130084,
32'h3fc90ff5,
32'h0ff47513,
32'h40b24422,
32'hb7d90141,
32'hfa800713,
32'hf793431c,
32'he793f877,
32'hc31c0407,
32'h71798082,
32'hd04ad226,
32'hcc52ce4e,
32'hd606ca56,
32'h892ad422,
32'h448189ae,
32'h4a116ac1,
32'h02091c63,
32'hfa000713,
32'hf7b3431c,
32'hdbfd0157,
32'h74134340,
32'h007c0ff4,
32'h802397a6,
32'h04850087,
32'hff4490e3,
32'h542250b2,
32'h54924532,
32'h49f25902,
32'h4ad24a62,
32'h80826145,
32'h450d3f71,
32'h00998433,
32'h85223fa1,
32'h450137ad,
32'h842a3f81,
32'hb7e13f3d,
32'hc6061141,
32'h45193741,
32'h40b23781,
32'hb7350141,
32'hce061101,
32'h45153f85,
32'h45013f05,
32'hc62a3735,
32'h40f23f29,
32'h61054532,
32'h11418082,
32'h3fc9c606,
32'h779337c5,
32'h557d0025,
32'h37a9cb81,
32'h37294511,
32'h37f93ded,
32'h857d057a,
32'h014140b2,
32'h71798082,
32'hd226d422,
32'hd606ce4e,
32'hcc52d04a,
32'hc62e84aa,
32'h49914401,
32'h97a2007c,
32'h0007ca03,
32'h3f193f51,
32'h3dd94509,
32'h00848933,
32'h35d5854a,
32'h35e98552,
32'h37793d6d,
32'hfd758905,
32'h1de30405,
32'h50b2fd34,
32'h54925422,
32'h49f25902,
32'h61454a62,
32'h06b78082,
32'h07130020,
32'h431cfa00,
32'hffe58ff5,
32'h8082c348,
32'hc84a1101,
32'h0513892a,
32'hce060300,
32'hca26cc22,
32'h3ff1c64e,
32'h07800513,
32'hffff14b7,
32'h44713fc9,
32'hb6c48493,
32'h57b359f1,
32'h8bbd0089,
32'hc50397a6,
32'h14710007,
32'h18e33f6d,
32'h40f2ff34,
32'h44d24462,
32'h49b24942,
32'h80826105,
32'hc4221141,
32'hc606c04a,
32'h842ac226,
32'h44834929,
32'h04050004,
32'h40b2e499,
32'h44924422,
32'h01414902,
32'h94638082,
32'h45350124,
32'h85263fbd,
32'hb7c53fad,
32'hc4221141,
32'h1537842a,
32'h0513ffff,
32'hc6069245,
32'h479537c1,
32'h02f40433,
32'hffff1537,
32'hb7c50513,
32'h377d9522,
32'hb07347a1,
32'h27833007,
32'h6741fe80,
32'hc7918ff9,
32'h24234785,
32'h2623fcf0,
32'ha001fc00,
32'hc686715d,
32'hc29ac496,
32'hde22c09e,
32'hda2adc26,
32'hd632d82e,
32'hd23ad436,
32'hce42d03e,
32'hca72cc46,
32'hc67ac876,
32'h24f3c47e,
32'h07b73420,
32'h079d8000,
32'h06f49663,
32'hfe802783,
32'h8ff96741,
32'h0713c799,
32'h471cfc00,
32'h0017c793,
32'h5401c71c,
32'h0737441c,
32'h8ff90002,
32'h33b5cf99,
32'h0713401c,
32'h56fdf900,
32'h953e8389,
32'h00f537b3,
32'h97aec714,
32'hc708c75c,
32'h54720001,
32'h42a640b6,
32'h43864316,
32'h555254e2,
32'h563255c2,
32'h571256a2,
32'h48725782,
32'h4e5248e2,
32'h4f324ec2,
32'h61614fa2,
32'h30200073,
32'h9963479d,
32'h07b700f4,
32'ha7838000,
32'hc3990007,
32'h3f094505,
32'h34102473,
32'hfe802783,
32'h00040737,
32'hcb858ff9,
32'hffff1537,
32'h92c50513,
32'h852635e1,
32'h05133db5,
32'h35950200,
32'h3d8d8522,
32'h02000513,
32'h25733da9,
32'h359d3430,
32'hffff1537,
32'h98450513,
32'h04113555,
32'h34141073,
32'h7179bfbd,
32'h4785c85a,
32'h80000b37,
32'hd606d422,
32'hd04ad226,
32'hcc52ce4e,
32'hc65eca56,
32'h2023c462,
32'h842a00fb,
32'h1537e115,
32'h0513ffff,
32'h35bd9385,
32'h004005b7,
32'h33118522,
32'h4788d7b7,
32'hafe78793,
32'h02f50c63,
32'ha02d4501,
32'hffff1537,
32'h95850513,
32'h053735b1,
32'h3bfd0040,
32'hffff1537,
32'h96450513,
32'h27833d35,
32'h0737fe80,
32'h8ff90008,
32'h450de399,
32'h3bb13db1,
32'hbfe5dd55,
32'h004009b7,
32'h00498593,
32'h39658522,
32'h85938a2a,
32'h85220089,
32'h2c03317d,
32'h8aaaff00,
32'hffca7b93,
32'h44814901,
32'h05b309b1,
32'h1c630139,
32'h94d60379,
32'hf0f94509,
32'hffff1537,
32'h96c50513,
32'h50b233e5,
32'h07b75422,
32'ha2238000,
32'h20230147,
32'h5492000b,
32'h49f25902,
32'h4ad24a62,
32'h4bb24b42,
32'h61454c22,
32'h85228082,
32'h07b339b9,
32'h94aa012c,
32'h0911c388,
32'h1141bf5d,
32'hc422c606,
32'hb07347a1,
32'h24033007,
32'hc119ff00,
32'h40400437,
32'hffff1537,
32'h97050513,
32'h85223b51,
32'h153733a1,
32'h0513ffff,
32'h33599805,
32'hfa002783,
32'hfe07cee3,
32'h000400e7,
32'h52450a07,
32'h00005f52,
32'h5252450a,
32'h4358455f,
32'h00000020,
32'h69617741,
32'h676e6974,
32'h6c656320,
32'h3376726c,
32'h78655f32,
32'h69622e65,
32'h2e2e2e6e,
32'h00000020,
32'h64616f4c,
32'h20676e69,
32'h00004028,
32'h2e2e2e29,
32'h0000000a,
32'h00004b4f,
32'h746f6f42,
32'h20676e69,
32'h6d6f7266,
32'h00000020,
32'h0a2e2e2e,
32'h0000000a,
32'h3c0a0a0a,
32'h4543203c,
32'h56524c4c,
32'h42203233,
32'h6c746f6f,
32'h6564616f,
32'h3e3e2072,
32'h4c420a0a,
32'h203a5644,
32'h20706553,
32'h32203132,
32'h0a343230,
32'h3a565748,
32'h00002020,
32'h4449430a,
32'h0020203a,
32'h4b4c430a,
32'h0020203a,
32'h53494d0a,
32'h00203a41,
32'h5349580a,
32'h00203a41,
32'h434f530a,
32'h0020203a,
32'h454d490a,
32'h00203a4d,
32'h74796220,
32'h40207365,
32'h00000000,
32'h454d440a,
32'h00203a4d,
32'h7475410a,
32'h6f6f626f,
32'h6e692074,
32'h2e733820,
32'h65725020,
32'h61207373,
32'h6b20796e,
32'h74207965,
32'h6261206f,
32'h2e74726f,
32'h0000000a,
32'h726f6241,
32'h2e646574,
32'h00000a0a,
32'h69617641,
32'h6c62616c,
32'h4d432065,
32'h0a3a7344,
32'h203a6820,
32'h706c6548,
32'h3a72200a,
32'h73655220,
32'h74726174,
32'h3a75200a,
32'h6c705520,
32'h0a64616f,
32'h203a7320,
32'h726f7453,
32'h6f742065,
32'h616c6620,
32'h200a6873,
32'h4c203a6c,
32'h2064616f,
32'h6d6f7266,
32'h616c6620,
32'h200a6873,
32'h42203a78,
32'h20746f6f,
32'h6d6f7266,
32'h616c6620,
32'h28206873,
32'h29504958,
32'h3a65200a,
32'h65784520,
32'h65747563,
32'h00000000,
32'h444d430a,
32'h00203e3a,
32'h65206f4e,
32'h75636578,
32'h6c626174,
32'h76612065,
32'h616c6961,
32'h2e656c62,
32'h00000000,
32'h74697257,
32'h00002065,
32'h74796220,
32'h74207365,
32'h5053206f,
32'h6c662049,
32'h20687361,
32'h00002040,
32'h7928203f,
32'h20296e2f,
32'h00000000,
32'h616c460a,
32'h6e696873,
32'h2e2e2e67,
32'h00000020,
32'h65206f4e,
32'h75636578,
32'h6c626174,
32'h00002e65,
32'h20296328,
32'h53207962,
32'h68706574,
32'h4e206e61,
32'h69746c6f,
32'h670a676e,
32'h75687469,
32'h6f632e62,
32'h74732f6d,
32'h746c6f6e,
32'h2f676e69,
32'h726f656e,
32'h00323376,
32'h61766e49,
32'h2064696c,
32'h00444d43,
32'h33323130,
32'h37363534,
32'h62613938,
32'h66656463,
32'h00455845,
32'h5a495300,
32'h48430045,
32'h4600534b,
32'h0048534c
};

// End of file