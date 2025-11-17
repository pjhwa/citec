import argparse
import logging
import time
import uuid
import multiprocessing
from tqdm import tqdm
import boto3
from botocore.exceptions import ClientError

# 로그 설정: 파일과 콘솔 출력
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('rgw_load_test.log'),
        logging.StreamHandler()
    ]
)

def parse_arguments():
    parser = argparse.ArgumentParser(description='Ceph RGW Load Test Script for Resharding Failure Induction')
    parser.add_argument('--endpoint', required=True, help='RGW endpoint URL (e.g., http://172.27.84.57:8088)')
    parser.add_argument('--access_key', required=True, help='S3 access key')
    parser.add_argument('--secret_key', required=True, help='S3 secret key')
    parser.add_argument('--bucket', required=True, help='Bucket name (e.g., abc-def-ghi-01)')
    parser.add_argument('--object_count', type=int, default=150000, help='Number of objects to create (default: 150000)')
    parser.add_argument('--tps', type=int, default=25, help='Transactions per second (default: 25)')
    parser.add_argument('--object_size', type=int, default=1024 * 1024, help='Object size in bytes (default: 1MB for network load)')
    parser.add_argument('--retries', type=int, default=3, help='Retry count on failure (default: 3)')
    return parser.parse_args()

def create_object(s3_client, bucket, key, body, retries):
    for attempt in range(retries):
        try:
            s3_client.put_object(Bucket=bucket, Key=key, Body=body)
            logging.info(f"PUT success: {key}")
            return True
        except ClientError as e:
            logging.warning(f"PUT attempt {attempt+1} failed for {key}: {e}")
            time.sleep(1)  # 지연 후 재시도
    logging.error(f"PUT failed after {retries} attempts: {key}")
    return False

def read_object(s3_client, bucket, key, retries):
    for attempt in range(retries):
        try:
            response = s3_client.get_object(Bucket=bucket, Key=key)
            data = response['Body'].read()  # 데이터 읽기 (메모리 부하 유발)
            logging.info(f"GET success: {key}, size: {len(data)}")
            return True
        except ClientError as e:
            logging.warning(f"GET attempt {attempt+1} failed for {key}: {e}")
            time.sleep(1)
    logging.error(f"GET failed after {retries} attempts: {key}")
    return False

def worker(task):
    s3_client, bucket, key, body, retries, operation = task
    if operation == 'put':
        return create_object(s3_client, bucket, key, body, retries)
    elif operation == 'get':
        return read_object(s3_client, bucket, key, retries)

def main():
    args = parse_arguments()
    
    # S3 클라이언트 생성 (insecure 허용 시 verify=False 추가 가능)
    s3 = boto3.client('s3',
                      endpoint_url=args.endpoint,
                      aws_access_key_id=args.access_key,
                      aws_secret_access_key=args.secret_key)
    
    # 객체 데이터: 반복 바이트로 크기 조정 (부하 유발)
    body = b'X' * args.object_size
    
    # 작업 목록 생성: 각 객체에 PUT + GET
    tasks = []
    for i in tqdm(range(args.object_count), desc="Preparing tasks"):
        key = f"load-test-{uuid.uuid4()}.eml"  # UUID로 고유 키, .eml 시뮬
        tasks.append((s3, args.bucket, key, body, args.retries, 'put'))
        tasks.append((s3, args.bucket, key, body, args.retries, 'get'))
    
    # multiprocessing Pool: CPU 코어 수 만큼 worker
    pool_size = multiprocessing.cpu_count() * 2  # IO-bound이므로 2배
    pool = multiprocessing.Pool(processes=pool_size)
    
    # TPS 제어: 배치로 나누어 시간 지연
    batch_size = args.tps * 2  # PUT+GET이므로 2배
    results = []
    with tqdm(total=len(tasks), desc="Executing load") as pbar:
        for i in range(0, len(tasks), batch_size):
            start_time = time.time()
            batch = tasks[i:i + batch_size]
            batch_results = pool.map(worker, batch)
            results.extend(batch_results)
            pbar.update(len(batch))
            
            # TPS 유지: 1초 대기 조정
            elapsed = time.time() - start_time
            if elapsed < 1:
                time.sleep(1 - elapsed)
    
    pool.close()
    pool.join()
    
    # 결과 요약
    success_count = sum(1 for r in results if r)
    logging.info(f"Total operations: {len(results)}, Success: {success_count}, Failure: {len(results) - success_count}")
    
    print("Load test completed. Check Ceph logs for resharding issues.")

if __name__ == "__main__":
    main()
