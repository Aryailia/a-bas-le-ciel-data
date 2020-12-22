// TODO: Not sure how to get this working with passing as STDIN to `| node -`
//import { promises as Fs } from 'fs';
const Fs = require('fs').promises;
//run: time node % json compiled/video.json

// Need this because we are of passing to node via STDIN
(async () => {
  const info_dir = process.argv[2];
  const target_path = process.argv[3];

  const json_info_list = await Fs.readdir(info_dir);

  const length = json_info_list.length;
  const result = new Array(length);
  for (let i = 0; i < length; ++i) {
    const filename = json_info_list[i];
    result[i] = Fs.readFile(`${info_dir}/${filename}`, "UTF8")
      .then(JSON.parse)
      .then(({ id, uploader_id, webpage_url, upload_date, title, description, thumbnail, thumbnails }) => {
        // Default to [entry].thumbnail, but prefers [entry].thumbnails 336 width
        const thumbnail_count = thumbnails.length;
        for (let j = 1; j < thumbnail_count; ++j) {
          const { url, width } = thumbnails[j];
          if (width == 336) {
            thumbnail = url;
          }
        }

        return {
          id,
          uploader_id,
          upload_date: upload_date,
          url: webpage_url,
          title,
          description,
          thumbnail,
        };
      })
      ;
  }

  const info_list = await Promise.all(result);
  const trimmed_info_list = info_list
    .filter(entry => entry.uploader_id == "HeiJinZhengZhi")
    .map(entry => { delete entry.uploader_id; return entry; })
    .sort((a, b) => a.upload_date > b.upload_date ? -1 : 1);
  Fs.writeFile(target_path, JSON.stringify(trimmed_info_list), "UTF8");
})();
