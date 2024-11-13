import http from 'k6/http';
import { sleep } from 'k6';
export const options = {
  vus: 10,
  duration: '3000s',
  //iterations: 40
};
export default function () {
  http.get('https://ssl-demo.kasunrajapakse.xyz');
  sleep(1);
}
