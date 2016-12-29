from setuptools import setup


setup(
    name='erulb_py',
    version='0.0.1a',
    author='timfeirg',
    zip_safe=True,
    author_email='timfeirg@icloud.com',
    description='ELB 3 python client',
    py_modules=['erulbpy'],
    install_requires=[
        'requests',
        'setuptools',
    ],
)
