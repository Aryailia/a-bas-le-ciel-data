// TODO: Not sure how to get this working with passing as STDIN to `| node -`
//import { promises as Fs } from 'fs';
const Fs = require('fs').promises;
//run: node % transcripts out

// Need this because we are of passing to node via STDIN
(async () => {
  const sub_dir = process.argv[2];
  const out_path = process.argv[3];

  const webttv_list = await Fs.readdir(sub_dir);
  //try {
  //  await Fs.mkdir(out);
  //} catch (err) {
  //  if (err.code != 'EEXIST') {
  //    console.log(err);
  //    process.exit(1);
  //  }
  //}

  const length = webttv_list.length;
  const result = new Array(length);
  let index = 0;
  for (let i = 0; i < length; ++i) {
    const filename = webttv_list[i];
    if (filename.endsWith(".vtt")) {
      result[index] = Fs.readFile(`${sub_dir}/${filename}`, "UTF8")
        .then(parse_webvtt)
        .then(text => ({
          id: filename.substring(0, 11), // youtube ids are 11 characters
          text,
        }))
        //.then(transcript => Fs.writeFile(`${out_dir}/${filename}`, transcript, "UTF8"));
      ++index;
    }
  }

  const output = await Promise.all(result);
  Fs.writeFile(out_path, JSON.stringify(output), "UTF8");
})();


function parse_webvtt(input_string) {
  if (typeof input_string !== "string") {
    throw new ParseError("Not a string");
  }
  // Guard against Windows "/r/n" (probably not necessary)
  input_string = input_string.replace(/\r\n|\r/, "\n");
  // Delimiter is a blank line
  const input = input_string.split('\n\n');

  if (!input[0].startsWith("WEBVTT") && !input[0].substring(1).startsWith("WEBVTT")) {
    throw new ParseError("Invalid vtt format: Does not start with 'WEBVTT' or '[BOM]WEBVTT'. [BOM] is a single byte");
  }

  const cues = parse_cues(input, 1);
  return cues.join("");
}

function parse_cues(input, start) {
  const length = input.length;
  //const output = new Array(Math.ceil(length / 2));
  const output = new Array(length - 1);
  let index = 0;
  let cache = " ";
  for (; start < length; ++start) {
    const cue = input[start].split("\n");
    if (cache != cue[2] && typeof cue[2] === "string") {
      cache = cue[2];
      //output[index] = cache;
      output[index] = cue[2].replace(/<[^>]*>/g, "");
      index += 1;
    }
  }
  //if (length > 0) {
  //  const cue = input[length - 1].split("\n");
  //  console.log(cue);
  //  //output[index] = cue[2].replace(/<.*>/g, "");
  //}
  return output.slice(0, index);
}


